`timescale 1ns / 1ps

module log_tb;

    // Clock and Reset Signals
    reg         sys_clk;
    reg         sys_rst_n;
    reg         log_clk;
    reg         log_rst_n;

    // Control and ADC Signals
    reg         i_log_sync;
    reg  [9:0]  i_adc_data;

    // Configuration parameters
    reg  [15:0] i_n_samples;
    reg  [7:0]  i_accum;
    reg  [3:0]  i_accum_type;
    reg  [3:0]  i_trans_meth;
    reg  [15:0] i_skip_ticks;

    // Readout Stream Interface
    wire [31:0] o_out_data;
    wire        o_out_vld;
    reg         i_out_rdy;
    wire        o_data_ready;
    wire [15:0] o_out_size;

    // -------------------------------------------------------------------------
    // 1. Clock Generation
    // -------------------------------------------------------------------------
    // sys_clk (80 MHz) -> Period = 12.5 ns (half-period = 6.25 ns)
    initial begin
        sys_clk = 1'b0;
        forever #6.25 sys_clk = ~sys_clk;
    end

    // log_clk (25 MHz) -> Period = 40 ns (half-period = 20 ns)
    initial begin
        log_clk = 1'b0;
        forever #20.00 log_clk = ~log_clk;
    end

    // -------------------------------------------------------------------------
    // 2. Device Under Test (DUT) Instantiation
    // -------------------------------------------------------------------------
    log #(
        .RAM_DEPTH (2048)
    ) uut (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .log_clk      (log_clk),
        .log_rst_n    (log_rst_n),
        .i_log_sync   (i_log_sync),
        .i_adc_data   (i_adc_data),
        .i_n_samples  (i_n_samples),
        .i_accum      (i_accum),
        .i_accum_type (i_accum_type),
        .i_trans_meth (i_trans_meth),
        .i_skip_ticks (i_skip_ticks),
        .o_out_data   (o_out_data),
        .o_out_vld    (o_out_vld),
        .i_out_rdy    (i_out_rdy),
        .o_data_ready (o_data_ready),
        .o_out_size   (o_out_size)
    );

    // -------------------------------------------------------------------------
    // 3. Emulating ADC Stream (log_clk Domain)
    // -------------------------------------------------------------------------
    reg [9:0] adc_ramp;
    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            adc_ramp   <= 10'd0;
            i_adc_data <= 10'd0;
        end else begin
            adc_ramp   <= adc_ramp + 1'b1;
            i_adc_data <= adc_ramp;
        end
    end

    // -------------------------------------------------------------------------
    // 4. Downstream Reader (sys_clk Domain)
    // -------------------------------------------------------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            i_out_rdy <= 1'b0;
        end else begin
            // Ready to read downstream data
            i_out_rdy <= 1'b1; 
        end
    end

    // -------------------------------------------------------------------------
    // 5. Task to trigger single sync pulse (log_clk Domain)
    // -------------------------------------------------------------------------
    task trigger_sync;
        begin
            @(posedge log_clk);
            #1;
            i_log_sync = 1'b1;
            @(posedge log_clk);
            #1;
            i_log_sync = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // 6. Test Stimulus Loop
    // -------------------------------------------------------------------------
    integer cycle;

    initial begin
        $dumpfile("log_tb.vcd");
        $dumpvars(0, log_tb);

        // Initialize Input Signals
        sys_rst_n    = 1'b0;
        log_rst_n    = 1'b0;
        i_log_sync   = 1'b0;
        i_n_samples  = 16'd0;
        i_accum      = 8'd0;
        i_accum_type = 4'd0;
        i_trans_meth = 4'd0;
        i_skip_ticks = 16'd0;

        // Apply Reset
        #100;
        sys_rst_n    = 1'b1;
        log_rst_n    = 1'b1;
        #200;

        $display("--- Starting Log Module Simulation with Variable Parameters ---");

        // Run 12 cycles, each separated by 200 us
        for (cycle = 1; cycle <= 12; cycle = cycle + 1) begin
            
            // Generate different parameters for each cycle
            i_n_samples  = 16'd64 + (cycle * 32);           // e.g. 96, 128, 160, 192 ...
            i_accum      = (cycle % 3) + 8'd1;              // 1, 2, 3
            i_accum_type = ((cycle % 2) == 0) ? 4'd1 : 4'd2;   // Alternate 1 (Peak) and 2 (Avg)
            i_trans_meth = ((cycle - 1) % 3) + 4'd1;        // Method 1, 2, 3
            i_skip_ticks = (cycle - 1) * 16'd5;             // Startup delays: 0, 5, 10, 15 ...

            $display("[%0t ns] [Cycle %0d/12] Triggering. Configuration: Samples=%0d, Accum=%0d, Type=%0d, TransMeth=%0d, SkipTicks=%0d", 
                     $time, cycle, i_n_samples, i_accum, i_accum_type, i_trans_meth, i_skip_ticks);

            // Send Sync Pulse
            trigger_sync();

            // Wait 200 microseconds (200,000 ns)
            #200000;
        end

        $display("--- Simulation completed successfully. ---");
        $finish;
    end

    // -------------------------------------------------------------------------
    // 7. Simulation Monitor Logs
    // -------------------------------------------------------------------------
    reg o_data_ready_d;
    always @(posedge sys_clk) begin
        o_data_ready_d <= o_data_ready;
        if (o_data_ready && !o_data_ready_d) begin
            $display("[%0t ns] >> Data Ready Detected! Size: %d words (32-bit)", $time, o_out_size);
        end
    end

    always @(posedge sys_clk) begin
        if (o_out_vld && i_out_rdy) begin
            $display("    [%0t ns] Read Data Word: 0x%h", $time, o_out_data);
        end
    end

endmodule