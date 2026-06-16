`timescale 1ns / 1ps

module vcd_tb;

    // =========================================================================
    // 1. Clock & Reset Declarations
    // =========================================================================
    reg sys_clk;
    reg sys_rst_n;
    reg log_clk;
    reg log_rst_n;

    // Clock Generation
    // sys_clk: 80 MHz -> 12.5 ns period (6.25 ns half-cycle)
    initial sys_clk = 1'b0;
    always #6.25 sys_clk = ~sys_clk;

    // log_clk: 25 MHz -> 40.0 ns period (20.0 ns half-cycle)
    initial log_clk = 1'b0;
    always #20.00 log_clk = ~log_clk;

    // =========================================================================
    // 2. Unit Under Test (UUT) Signals
    // =========================================================================
    reg         i_log_sync;
    reg  [9:0]  i_adc_data;
    reg  [15:0] i_n_samples;
    reg  [7:0]  i_accum;
    reg  [3:0]  i_accum_type;
    reg  [3:0]  i_trans_meth;
    reg  [15:0] i_skip_ticks;

    wire [31:0] o_out_data;
    wire        o_out_vld;
    reg         i_out_rdy;
    wire        o_data_ready;
    wire [15:0] o_out_size;

    // =========================================================================
    // 3. UUT Instantiation (RAM Depth reduced for compact simulation tracing)
    // =========================================================================
    log #(
        .RAM_DEPTH(128)
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

    // =========================================================================
    // 4. Downstream Ready Handshake Emulation with Random Backpressure
    // =========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            i_out_rdy <= 1'b0;
        end else begin
            if (o_data_ready) begin
                // Randomly assert/de-assert i_out_rdy to verify robust handshaking
                i_out_rdy <= ($random % 10) > 2; // 70% ready density
            end else begin
                i_out_rdy <= 1'b0;
            end
        end
    end

    // Monitor read transactions
    always @(posedge sys_clk) begin
        if (o_out_vld && i_out_rdy) begin
            $display("[t=%0t ns] [SYS_CLK] Outbound Word Readout: 0x%08h", $time, o_out_data);
        end
    end

    // =========================================================================
    // 5. Test Stimulus Sequence
    // =========================================================================
    integer i;

    initial begin
        // Output Dump configuration
        $dumpfile("vcd_tb.vcd");
        $dumpvars(0, vcd_tb);

        // Initial inputs state
        sys_rst_n    = 1'b0;
        log_rst_n    = 1'b0;
        i_log_sync   = 1'b0;
        i_adc_data   = 10'd0;
        i_n_samples  = 16'd0;
        i_accum      = 8'd0;
        i_accum_type = 4'd0;
        i_trans_meth = 4'd0;
        i_skip_ticks = 16'd0;

        // Reset sequence
        #100;
        @(posedge sys_clk);
        sys_rst_n = 1'b1;
        $display("[t=%0t ns] System Reset De-asserted.", $time);
        
        @(posedge log_clk);
        log_rst_n = 1'b1;
        $display("[t=%0t ns] Log ADC Reset De-asserted.", $time);

        #80;

        // ---------------------------------------------------------------------
        // FRAME 1: Peak Decimation (accum=2), >>2 shift, skip_ticks=4, n_samples=16
        // Expected decimated samples: 16/2 = 8 samples (8 bytes = 2 words)
        // ---------------------------------------------------------------------
        $display("\n--- [t=%0t ns] STARTING FRAME 1 CONFIGURATION ---", $time);
        i_n_samples  = 16'd16;
        i_accum      = 8'd2;      // Accumulate 2 raw samples
        i_accum_type = 4'd1;      // Mode: Peak detector
        i_trans_meth = 4'd1;      // Mode: Shift right by 2 (>> 2)
        i_skip_ticks = 16'd4;     // Wait 4 log_clk periods before capturing

        @(posedge log_clk);
        i_log_sync = 1'b1;
        @(posedge log_clk);
        i_log_sync = 1'b0;
        $display("[t=%0t ns] Sync Pulse Triggered.", $time);

        // Let skip_ticks delay elapse
        repeat(4) @(posedge log_clk);

        // Feed 16 sequential ADC samples
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge log_clk);
            i_adc_data = 10'd400 + (i * 12); // Sample values incrementing
            $display("[t=%0t ns] [LOG_CLK] Raw Sample Injected: %0d", $time, i_adc_data);
        end
        @(posedge log_clk);
        i_adc_data = 10'd0;

        // Wait until Frame 1 buffer becomes ready for reading
        @(posedge o_data_ready);
        $display("[t=%0t ns] [SYS_CLK] Frame 1 Packet Ready. Word Count: %0d", $time, o_out_size);

        // Wait for readout to finish in sys_clk domain
        while (o_data_ready) @(posedge sys_clk);
        $display("[t=%0t ns] [SYS_CLK] Frame 1 Readout complete.", $time);

        #400;

        // ---------------------------------------------------------------------
        // FRAME 2: Integrator/Average Decimation (accum=4), Saturation, skip_ticks=0, n_samples=32
        // Expected decimated samples: 32/4 = 8 samples (8 bytes = 2 words)
        // ---------------------------------------------------------------------
        $display("\n--- [t=%0t ns] STARTING FRAME 2 CONFIGURATION (Ping-Pong Swap) ---", $time);
        i_n_samples  = 16'd32;
        i_accum      = 8'd4;      // Accumulate 4 raw samples
        i_accum_type = 4'd2;      // Mode: Integration / Average
        i_trans_meth = 4'd2;      // Mode: Saturation format
        i_skip_ticks = 16'd0;     // Start processing immediately

        @(posedge log_clk);
        i_log_sync = 1'b1;
        @(posedge log_clk);
        i_log_sync = 1'b0;
        $display("[t=%0t ns] Sync Pulse Triggered.", $time);

        // Feed 32 sequential ADC samples
        for (i = 0; i < 32; i = i + 1) begin
            @(posedge log_clk);
            i_adc_data = 10'd150 + (i * 8);
            $display("[t=%0t ns] [LOG_CLK] Raw Sample Injected: %0d", $time, i_adc_data);
        end
        @(posedge log_clk);
        i_adc_data = 10'd0;

        // Wait until Frame 2 buffer becomes ready for reading
        @(posedge o_data_ready);
        $display("[t=%0t ns] [SYS_CLK] Frame 2 Packet Ready. Word Count: %0d", $time, o_out_size);

        // Wait for readout to finish in sys_clk domain
        while (o_data_ready) @(posedge sys_clk);
        $display("[t=%0t ns] [SYS_CLK] Frame 2 Readout complete.", $time);

        #1000;
        $display("\n[t=%0t ns] Simulation finished successfully.", $time);
        $finish;
    end

endmodule