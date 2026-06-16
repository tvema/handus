// =========================================================================
// Module: log
// Description: Collects, processes (decimation, compression, packing), 
//              and buffers ADC data from a logarithmic amplifier.
//              Handles CDC between log_clk (25 MHz) and sys_clk (80 MHz).
// =========================================================================

`timescale 1ns / 1ps

module log #(
    parameter RAM_DEPTH = 2048 // 2048 x 32-bit words per buffer
) (
    // Clock & Reset Domains
    input  wire        sys_clk,          // 80 MHz System Clock
    input  wire        sys_rst_n,        // Reset synchronized to sys_clk (active low)
    input  wire        log_clk,          // 25 MHz Log ADC Clock
    input  wire        log_rst_n,        // Reset synchronized to log_clk (active low)

    // Sync input in log_clk domain
    input  wire        i_log_sync,       // External sync trigger

    // ADC Raw Data input (log_clk domain)
    input  wire [9:0]  i_adc_data,       // 10-bit raw ADC samples

    // Configuration Parameters (stable during capture)
    input  wire [15:0] i_n_samples,      // Total raw samples to capture
    input  wire [7:0]  i_accum,          // Accumulation decimation rate
    input  wire [3:0]  i_accum_type,     // 1 = Peak detector, 2 = Integrator/Average
    input  wire [3:0]  i_trans_meth,     // 1 = >>2, 2 = Saturation, 3 = >>1 + Saturation
    input  wire [15:0] i_skip_ticks,     // Startup delay in log_clk cycles

    // Readout Stream Interface (sys_clk domain)
    output reg  [31:0] o_out_data,       // Packed 32-bit output stream
    output reg         o_out_vld,        // Stream valid
    input  wire        i_out_rdy,        // Downstream ready
    output reg         o_data_ready,     // Buffer packet ready flag
    output reg  [15:0] o_out_size        // Total 32-bit words in ready packet
);

    // Address width calculation
    localparam ADDR_W = $clog2(RAM_DEPTH);

    // =========================================================================
    // 1. Dual-Port Ping-Pong Memory Architecture
    // =========================================================================
    // Write Ports (log_clk domain)
    reg             ram0_we;
    reg             ram1_we;
    reg  [ADDR_W-1:0] ram0_waddr;
    reg  [ADDR_W-1:0] ram1_waddr;
    reg  [31:0]     ram0_wdata;
    reg  [31:0]     ram1_wdata;

    // Read Ports (sys_clk domain)
    reg  [ADDR_W-1:0] raddr;
    wire            ram_re; // Pre-fetch controlled read enable

    `ifdef TESTMODE
        // Behavioral memory for simulation (will also be inferred by Quartus)
        reg [31:0] ram0 [0:RAM_DEPTH-1];
        reg [31:0] ram1 [0:RAM_DEPTH-1];
        reg [31:0] ram0_q;
        reg [31:0] ram1_q;

        always @(posedge log_clk) begin
            if (ram0_we) ram0[ram0_waddr] <= ram0_wdata;
        end
        always @(posedge log_clk) begin
            if (ram1_we) ram1[ram1_waddr] <= ram1_wdata;
        end

        // Read data outputs latching
        always @(posedge sys_clk) begin
            if (ram_re) begin
                ram0_q <= ram0[raddr];
                ram1_q <= ram1[raddr];
            end
        end
    `else
        // Synthesizable block RAM using Quartus Dual-Port RAM IP
        wire [31:0] ram0_q;
        wire [31:0] ram1_q;

        log_dpram #(
            .RAM_DEPTH (RAM_DEPTH),
            .ADDR_W    (ADDR_W)
        ) u_ram0 (
            .wclk  (log_clk),
            .we    (ram0_we),
            .waddr (ram0_waddr),
            .wdata (ram0_wdata),
            .rclk  (sys_clk),
            .re    (ram_re),
            .raddr (raddr),
            .rdata (ram0_q)
        );

        log_dpram #(
            .RAM_DEPTH (RAM_DEPTH),
            .ADDR_W    (ADDR_W)
        ) u_ram1 (
            .wclk  (log_clk),
            .we    (ram1_we),
            .waddr (ram1_waddr),
            .wdata (ram1_wdata),
            .rclk  (sys_clk),
            .re    (ram_re),
            .raddr (raddr),
            .rdata (ram1_q)
        );
    `endif

    // =========================================================================
    // 2. Clock Domain Crossing (CDC) Flags & Handshakes
    // =========================================================================
    // Toggle flags used to signal state transitions between asynchronous clocks
    reg [1:0] buf_ready_toggle; // log_clk -> sys_clk
    reg [1:0] buf_free_toggle;  // sys_clk -> log_clk

    // Sync Ready Flags to sys_clk domain
    reg [1:0] sync_ready0;
    reg [1:0] sync_ready1;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            sync_ready0 <= 2'b0;
            sync_ready1 <= 2'b0;
        end else begin
            sync_ready0 <= {sync_ready0[0], buf_ready_toggle[0]};
            sync_ready1 <= {sync_ready1[0], buf_ready_toggle[1]};
        end
    end
    wire buf_ready_toggle_sync0 = sync_ready0[1];
    wire buf_ready_toggle_sync1 = sync_ready1[1];

    // Sync Free Flags to log_clk domain
    reg [1:0] sync_free0;
    reg [1:0] sync_free1;
    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            sync_free0 <= 2'b0;
            sync_free1 <= 2'b0;
        end else begin
            sync_free0 <= {sync_free0[0], buf_free_toggle[0]};
            sync_free1 <= {sync_free1[0], buf_free_toggle[1]};
        end
    end
    wire buf_free_toggle_sync0 = sync_free0[1];
    wire buf_free_toggle_sync1 = sync_free1[1];

    // =========================================================================
    // 3. Write and Processing Logic (log_clk Domain)
    // =========================================================================
    localparam ST_IDLE       = 3'd0;
    localparam ST_SKIP       = 3'd1;
    localparam ST_CAPTURE    = 3'd2;
    localparam ST_PIPE_WAIT  = 3'd3;
    localparam ST_DONE       = 3'd4;

    reg [2:0]  state;
    reg        write_buf_sel; // 0 = Buffer A (ram0), 1 = Buffer B (ram1)

    // Track if target buffer is free to write
    wire is_buf_free = (write_buf_sel == 0) ? 
                       (buf_free_toggle_sync0 == buf_ready_toggle[0]) :
                       (buf_free_toggle_sync1 == buf_ready_toggle[1]);

    reg [15:0] skip_cnt;
    reg [15:0] raw_cnt;
    reg [2:0]  pipe_cnt;
    reg [15:0] buf_size [0:1];
    reg [ADDR_W-1:0] write_addr;

    // Last sample flag in packet
    wire sample_last = (raw_cnt == i_n_samples - 1);

    // Submodule Wiring
    wire [9:0] decim_data;
    wire       decim_vld;
    wire       decim_last;

    wire [7:0] comp_data;
    wire       comp_vld;
    wire       comp_last;

    wire [31:0] pack_word;
    wire        pack_write;

    // 3.1. Decimator Instance
    log_decimator u_log_decimator (
        .log_clk      (log_clk),
        .log_rst_n    (log_rst_n),
        .i_data       (i_adc_data),
        .i_vld        (state == ST_CAPTURE),
        .i_last       ((state == ST_CAPTURE) && sample_last),
        .i_accum      (i_accum),
        .i_accum_type (i_accum_type),
        .o_data       (decim_data),
        .o_vld        (decim_vld),
        .o_last       (decim_last)
    );

    // 3.2. Compressor Instance
    log_compressor u_log_compressor (
        .log_clk      (log_clk),
        .log_rst_n    (log_rst_n),
        .i_data       (decim_data),
        .i_vld        (decim_vld),
        .i_last       (decim_last),
        .i_trans_meth (i_trans_meth),
        .o_data       (comp_data),
        .o_vld        (comp_vld),
        .o_last       (comp_last)
    );

    // 3.3. Packer Instance
    log_packer u_log_packer (
        .log_clk      (log_clk),
        .log_rst_n    (log_rst_n),
        .i_data       (comp_data),
        .i_vld        (comp_vld),
        .i_last       (comp_last),
        .i_sync       (i_log_sync),
        .o_word       (pack_word),
        .o_write      (pack_write)
    );

    // State machine controls
    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            state            <= ST_IDLE;
            skip_cnt         <= 16'd0;
            raw_cnt          <= 16'd0;
            pipe_cnt         <= 3'd0;
            write_buf_sel    <= 1'b0;
            buf_ready_toggle <= 2'b00;
            buf_size[0]      <= 16'd0;
            buf_size[1]      <= 16'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (i_log_sync && is_buf_free) begin
                        skip_cnt  <= 16'd0;
                        raw_cnt   <= 16'd0;
                        if (i_skip_ticks == 16'd0) begin
                            state <= ST_CAPTURE;
                        end else begin
                            state <= ST_SKIP;
                        end
                    end
                end

                ST_SKIP: begin
                    skip_cnt <= skip_cnt + 16'd1;
                    if (skip_cnt + 16'd1 == i_skip_ticks) begin
                        state <= ST_CAPTURE;
                    end
                end

                ST_CAPTURE: begin
                    raw_cnt <= raw_cnt + 16'd1;
                    if (sample_last) begin
                        state    <= ST_PIPE_WAIT;
                        pipe_cnt <= 3'd2; // Wait 3 cycles total for complete pipeline drain
                    end
                end

                ST_PIPE_WAIT: begin
                    if (pipe_cnt == 3'd0) begin
                        state <= ST_DONE;
                    end else begin
                        pipe_cnt <= pipe_cnt - 3'd1;
                    end
                end

                ST_DONE: begin
                    // Store size and toggle buffer ready flag for read-out side
                    buf_size[write_buf_sel] <= write_addr;
                    buf_ready_toggle[write_buf_sel] <= ~buf_ready_toggle[write_buf_sel];
                    write_buf_sel <= ~write_buf_sel;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // RAM Write Routing
    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            write_addr <= {ADDR_W{1'b0}};
            ram0_we    <= 1'b0;
            ram1_we    <= 1'b0;
            ram0_wdata <= 32'd0;
            ram1_wdata <= 32'd0;
            ram0_waddr <= {ADDR_W{1'b0}};
            ram1_waddr <= {ADDR_W{1'b0}};
        end else begin
            ram0_we <= 1'b0;
            ram1_we <= 1'b0;

            if (state == ST_IDLE && i_log_sync && is_buf_free) begin
                write_addr <= {ADDR_W{1'b0}};
            end else if (pack_write) begin
                write_addr <= write_addr + 1'b1;
                if (write_buf_sel == 1'b0) begin
                    ram0_we    <= 1'b1;
                    ram0_waddr <= write_addr;
                    ram0_wdata <= pack_word;
                end else begin
                    ram1_we    <= 1'b1;
                    ram1_waddr <= write_addr;
                    ram1_wdata <= pack_word;
                end
            end
        end
    end


    // =========================================================================
    // 4. Buffer Readout Control Logic (sys_clk Domain)
    // =========================================================================
    localparam RD_IDLE     = 2'd0;
    localparam RD_PREFETCH = 2'd1;
    localparam RD_STREAM   = 2'd2;

    reg [1:0]  rd_state;
    reg        sys_read_buf_sel; // Active read buffer pointer
    reg [15:0] rcnt;

    // Detect if targeted buffer has finished writing and has pending data
    wire is_ready = (sys_read_buf_sel == 0) ? 
                    (buf_ready_toggle_sync0 != buf_free_toggle[0]) :
                    (buf_ready_toggle_sync1 != buf_free_toggle[1]);

    // Read Enable control to prefetch and hold block RAM values bubble-free
    assign ram_re = (rd_state == RD_IDLE && is_ready) || 
                    (rd_state == RD_PREFETCH) || 
                    (rd_state == RD_STREAM && i_out_rdy);

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            raddr            <= {ADDR_W{1'b0}};
            rcnt             <= 16'd0;
            o_out_vld        <= 1'b0;
            o_data_ready     <= 1'b0;
            o_out_size       <= 16'd0;
            sys_read_buf_sel <= 1'b0;
            buf_free_toggle  <= 2'b00;
            rd_state         <= RD_IDLE;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (is_ready) begin
                        o_data_ready <= 1'b1;
                        o_out_size   <= buf_size[sys_read_buf_sel];
                        raddr        <= {ADDR_W{1'b0}};
                        rcnt         <= 16'd0;
                        rd_state     <= RD_PREFETCH;
                    end
                end

                RD_PREFETCH: begin
                    // 1 bubble cycle to account for RAM output register latency
                    raddr    <= raddr + 1'b1;
                    rd_state <= RD_STREAM;
                end

                RD_STREAM: begin
                    o_out_vld <= 1'b1;
                    if (i_out_rdy) begin
                        rcnt <= rcnt + 16'd1;
                        if (rcnt + 16'd1 == o_out_size) begin
                            o_out_vld        <= 1'b0;
                            o_data_ready     <= 1'b0;
                            // Release/free current buffer
                            buf_free_toggle[sys_read_buf_sel] <= ~buf_free_toggle[sys_read_buf_sel];
                            sys_read_buf_sel <= ~sys_read_buf_sel;
                            rd_state         <= RD_IDLE;
                        end else begin
                            raddr <= raddr + 1'b1;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // Direct assignment of correct active buffer to the data output
    always @(*) begin
        if (sys_read_buf_sel == 1'b0) begin
            o_out_data = ram0_q;
        end else begin
            o_out_data = ram1_q;
        end
    end

endmodule


// =========================================================================
// Helper Submodule: log_decimator
// Description: Handles decimation accumulation and peak calculation logic
// =========================================================================
module log_decimator (
    input  wire        log_clk,
    input  wire        log_rst_n,
    input  wire [9:0]  i_data,
    input  wire        i_vld,
    input  wire        i_last,
    input  wire [7:0]  i_accum,
    input  wire [3:0]  i_accum_type,
    output reg  [9:0]  o_data,
    output reg         o_vld,
    output reg         o_last
);

    reg [17:0] sum_reg;
    reg [9:0]  peak_reg;
    reg [7:0]  count_reg;
    reg        last_seen;

    wire [7:0] eff_accum = (i_accum == 8'd0) ? 8'd1 : i_accum;

    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            sum_reg   <= 18'd0;
            peak_reg  <= 10'd0;
            count_reg <= 8'd0;
            last_seen <= 1'b0;
            o_data    <= 10'd0;
            o_vld     <= 1'b0;
            o_last    <= 1'b0;
        end else begin
            o_vld  <= 1'b0;
            o_last <= 1'b0;
            if (i_vld) begin
                if (count_reg == 8'd0) begin
                    sum_reg   <= i_data;
                    peak_reg  <= i_data;
                    last_seen <= i_last;

                    if (eff_accum == 8'd1 || i_last) begin
                        o_vld     <= 1'b1;
                        o_data    <= i_data;
                        o_last    <= i_last;
                        count_reg <= 8'd0;
                    end else begin
                        count_reg <= 8'd1;
                    end
                end else if (count_reg == eff_accum - 1'b1 || i_last) begin
                    o_vld  <= 1'b1;
                    o_last <= last_seen | i_last;
                    if (i_accum_type == 4'd1) begin
                        o_data <= (i_data > peak_reg) ? i_data : peak_reg;
                    end else begin
                        o_data <= (sum_reg + i_data) / (count_reg + 1'b1);
                    end
                    count_reg <= 8'd0;
                end else begin
                    sum_reg   <= sum_reg + i_data;
                    peak_reg  <= (i_data > peak_reg) ? i_data : peak_reg;
                    last_seen <= last_seen | i_last;
                    count_reg <= count_reg + 1'b1;
                end
            end
        end
    end

endmodule


// =========================================================================
// Helper Submodule: log_compressor
// Description: Down-samples 10-bit raw ADC to 8-bit dynamic compressed format
// =========================================================================
module log_compressor (
    input  wire        log_clk,
    input  wire        log_rst_n,
    input  wire [9:0]  i_data,
    input  wire        i_vld,
    input  wire        i_last,
    input  wire [3:0]  i_trans_meth,
    output reg  [7:0]  o_data,
    output reg         o_vld,
    output reg         o_last
);

    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            o_data <= 8'd0;
            o_vld  <= 1'b0;
            o_last <= 1'b0;
        end else begin
            o_vld  <= i_vld;
            o_last <= i_last;
            if (i_vld) begin
                case (i_trans_meth)
                    4'd1: begin // Shift Right (>> 2)
                        o_data <= i_data[9:2];
                    end
                    4'd2: begin // Saturation
                        o_data <= (i_data > 10'h0FF) ? 8'hFF : i_data[7:0];
                    end
                    4'd3: begin // Shift 1 & Saturation
                        o_data <= (i_data[9:1] > 9'h0FF) ? 8'hFF : i_data[8:1];
                    end
                    default: begin
                        o_data <= i_data[7:0];
                    end
                endcase
            end
        end
    end

endmodule


// =========================================================================
// Helper Submodule: log_packer
// Description: Packs incoming bytes into 32-bit words, handling unaligned ends
// =========================================================================
module log_packer (
    input  wire        log_clk,
    input  wire        log_rst_n,
    input  wire [7:0]  i_data,
    input  wire        i_vld,
    input  wire        i_last,
    input  wire        i_sync,
    output reg  [31:0] o_word,
    output reg         o_write
);

    reg [1:0]  byte_cnt;
    reg [23:0] pack_reg;

    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            byte_cnt <= 2'd0;
            pack_reg <= 24'd0;
            o_word   <= 32'd0;
            o_write  <= 1'b0;
        end else begin
            o_write <= 1'b0;

            if (i_sync) begin
                byte_cnt <= 2'd0;
                pack_reg <= 24'd0;
            end else if (i_vld) begin
                if (byte_cnt == 2'd3 || i_last) begin
                    o_write  <= 1'b1;
                    byte_cnt <= 2'd0;
                    case (byte_cnt)
                        2'd0: o_word <= {24'h0, i_data};
                        2'd1: o_word <= {16'h0, i_data, pack_reg[7:0]};
                        2'd2: o_word <= {8'h0,  i_data, pack_reg[15:8], pack_reg[7:0]};
                        2'd3: o_word <= {i_data, pack_reg[23:16], pack_reg[15:8], pack_reg[7:0]};
                    endcase
                end else begin
                    case (byte_cnt)
                        2'd0: pack_reg[7:0]   <= i_data;
                        2'd1: pack_reg[15:8]  <= i_data;
                        2'd2: pack_reg[23:16] <= i_data;
                    endcase
                    byte_cnt <= byte_cnt + 2'd1;
                end
            end
        end
    end

endmodule


// =========================================================================
// Helper Submodule: log_dpram
// Description: Dual-clock, dual-port RAM using Quartus altsyncram megafunction
// =========================================================================
`ifndef TESTMODE
module log_dpram #(
    parameter RAM_DEPTH = 2048,
    parameter ADDR_W = 11
) (
    input  wire              wclk,   // Write Clock (log_clk)
    input  wire              we,     // Write Enable
    input  wire [ADDR_W-1:0] waddr,  // Write Address
    input  wire [31:0]       wdata,  // Write Data
    input  wire              rclk,   // Read Clock (sys_clk)
    input  wire              re,     // Read Enable
    input  wire [ADDR_W-1:0] raddr,  // Read Address
    output wire [31:0]       rdata   // Read Data Out
);

    altsyncram #(
        .address_reg_b             ("CLOCK1"),
        .clock_enable_input_a      ("BYPASS"),
        .clock_enable_input_b      ("NORMAL"),
        .clock_enable_output_b     ("BYPASS"),
        .intended_device_family    ("Cyclone IV E"),
        .numwords_a                (RAM_DEPTH),
        .numwords_b                (RAM_DEPTH),
        .operation_mode            ("DUAL_PORT"),
        .outdata_aclr_b            ("NONE"),
        .outdata_reg_b             ("UNREGISTERED"),
        .power_up_uninitialized    ("FALSE"),
        .widthad_a                 (ADDR_W),
        .widthad_b                 (ADDR_W),
        .width_a                   (32),
        .width_b                   (32),
        .width_byteena_a           (1)
    ) altsyncram_component (
        .address_a (waddr),
        .address_b (raddr),
        .clock0    (wclk),
        .clock1    (rclk),
        .clocken1  (re),
        .data_a    (wdata),
        .wren_a    (we),
        .q_b       (rdata),
        .aclr0     (1'b0),
        .aclr1     (1'b0),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a (1'b1),
        .byteena_b (1'b1),
        .clocken0  (1'b1),
        .clocken2  (1'b1),
        .clocken3  (1'b1),
        .data_b    ({32{1'b1}}),
        .eccstatus (),
        .q_a       (),
        .rden_b    (1'b1),
        .wren_b    (1'b0)
    );

endmodule
`endif