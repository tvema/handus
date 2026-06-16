`timescale 1ns / 1ps

module vrc_tb;

    parameter P = 16; // Number of fractional bits for fixed-point calculations

    // Clocks and Resets (according to global configuration rules)
    reg         dac_clk;          // dac_clk: 50MHz
    reg         dac_rst_n;        // Active-low reset for dac_clk domain
    
    reg         i_dac_sync;       // Start sync pulse (synchronized to dac_clk)

    // Configuration parameters for VRC
    reg [1:0]   i_vrc_type;       // 00: Constant, 01: Sequential, 10: Parallel
    reg [7:0]   i_dac_div;        // DAC update rate divider
    reg [15:0]  i_start_delay;    // Delay before ramp (in dac_clk cycles)
    reg [10:0]  i_init_gain;      // Initial gain
    reg [31:0]  i_rate_1;         // Ramp rate 1 (float scaled by 2^P)
    reg [15:0]  i_duration_1;     // Duration 1 (in update steps)
    reg [31:0]  i_rate_2;         // Ramp rate 2 (float scaled by 2^P)
    reg [15:0]  i_duration_2;     // Duration 2 (in update steps)
    reg [9:0]   i_dac_min;        // Min DAC limit
    reg [9:0]   i_dac_max;        // Max DAC limit

    // Interconnect between VRC and DAC SPI controllers
    wire        o_dac_vld;
    wire        o_dac_data_vld;   // Trigger for SPI transmission
    wire [9:0]  o_dac1;           // 10-bit code for DAC 1
    wire [9:0]  o_dac2;           // 10-bit code for DAC 2

    // DAC SPI Ready signals
    wire        o_dac1_rdy;       // Ready signal from DAC 1 SPI
    wire        o_dac2_rdy;       // Ready signal from DAC 2 SPI
    
    // Combined ready status: Both SPI channels must be ready to receive new parameters
    wire        i_dac_rdy = o_dac1_rdy && o_dac2_rdy;

    // SPI Outputs for physical DACs (DAC101S101)
    wire        o_sclk1;          // SPI Clock for DAC 1
    wire        o_sync1_n;        // SPI SYNC_N (CS_n) for DAC 1
    wire        o_din1;           // SPI MOSI (SDIN) for DAC 1

    wire        o_sclk2;          // SPI Clock for DAC 2
    wire        o_sync2_n;        // SPI SYNC_N (CS_n) for DAC 2
    wire        o_din2;           // SPI MOSI (SDIN) for DAC 2


    // =====================================================================
    // 1. UNIT UNDER TEST: VRC (Variable Ramp Controller)
    // =====================================================================
    vrc #(
        .P(P)
    ) uut_vrc (
        .dac_clk(dac_clk),
        .dac_rst_n(dac_rst_n),
        .i_dac_sync(i_dac_sync),
        .i_vrc_type(i_vrc_type),
        .i_dac_div(i_dac_div),
        .i_start_delay(i_start_delay),
        .i_init_gain(i_init_gain),
        .i_rate_1(i_rate_1),
        .i_duration_1(i_duration_1),
        .i_rate_2(i_rate_2),
        .i_duration_2(i_duration_2),
        .i_dac_min(i_dac_min),
        .i_dac_max(i_dac_max),
        .i_dac_rdy(i_dac_rdy),
        .o_dac_vld(o_dac_vld),
        .o_dac_data_vld(o_dac_data_vld),
        .o_dac1(o_dac1),
        .o_dac2(o_dac2)
    );

    // =====================================================================
    // 2. DAC SPI INSTANCES (Connected to UUT VRC outputs)
    // =====================================================================
    
    // DAC 1 SPI Transmitter
    dac_spi dac1_spi_inst (
        .dac_clk(dac_clk),
        .dac_rst_n(dac_rst_n),
        .i_dac_data(o_dac1),
        .i_dac_data_vld(o_dac_data_vld),
        .o_dac_data_rdy(o_dac1_rdy),
        .o_dac_sclk(o_sclk1),
        .o_dac_sdin(o_din1),
        .o_dac_sync_n(o_sync1_n)
    );

    // DAC 2 SPI Transmitter
    dac_spi dac2_spi_inst (
        .dac_clk(dac_clk),
        .dac_rst_n(dac_rst_n),
        .i_dac_data(o_dac2),
        .i_dac_data_vld(o_dac_data_vld),
        .o_dac_data_rdy(o_dac2_rdy),
        .o_dac_sclk(o_sclk2),
        .o_dac_sdin(o_din2),
        .o_dac_sync_n(o_sync2_n)
    );


    // =====================================================================
    // CLOCK GENERATION
    // =====================================================================

    // dac_clk: 50 MHz (Period = 20 ns -> Half-period = 10.0 ns)
    always begin
        #10.0 dac_clk = ~dac_clk;
    end


    // =====================================================================
    // TEST SCENARIOS
    // =====================================================================
    initial begin
        // Setup GTKWave/VCD dump
        $dumpfile("vrc_tb.vcd");
        $dumpvars(0, vrc_tb);

        // Initialize signals
        dac_clk       = 1'b0;
        dac_rst_n     = 1'b0;
        i_dac_sync    = 1'b0;
        i_vrc_type    = 2'b00;
        i_dac_div     = 8'd1;
        i_start_delay = 16'd0;
        i_init_gain   = 11'd0;
        i_rate_1      = 32'd0;
        i_duration_1  = 16'd0;
        i_rate_2      = 32'd0;
        i_duration_2  = 16'd0;
        i_dac_min     = 10'd100;
        i_dac_max     = 10'd900;

        // Apply Reset
        #100;
        @(posedge dac_clk);
        dac_rst_n = 1'b1;
        #50;

        // =====================================================================
        // TEST 1: Constant/Bypass Mode (i_vrc_type = 2'b00)
        // Expected behavior: Outputs immediately latch onto init_gain on both DACs
        // =====================================================================
        $display("[TB] Starting Test 1: Constant/Bypass Mode (2'b00)...");
        @(posedge dac_clk);
        i_vrc_type    = 2'b00;
        i_init_gain   = 11'd500;
        i_dac_min     = 10'd100;
        i_dac_max     = 10'd900;
        i_dac_sync    = 1'b1;
        
        @(posedge dac_clk);
        i_dac_sync    = 1'b0;
        
        repeat (10) @(posedge dac_clk);
        $display("[TB] Test 1 Results -> DAC1 Code: %d, DAC2 Code: %d", o_dac1, o_dac2);
        
        if (o_dac1 == 10'd500 && o_dac2 == 10'd500) begin
            $display("[TB] Test 1 PASSED!");
        end else begin
            $display("[TB] Test 1 FAILED!");
        end

        // =====================================================================
        // TEST 2: Sequential Mode (i_vrc_type = 2'b01)
        // Expected behavior: DAC1 ramps up to max first, then excess ramps DAC2
        // =====================================================================
        $display("[TB] Starting Test 2: Sequential Mode (2'b01)...");
        @(posedge dac_clk);
        i_vrc_type    = 2'b01;
        i_dac_div     = 8'd2;        // Update steps occur every 2 clocks
        i_start_delay = 16'd10;      // 10-clock wait period before ramp start
        i_init_gain   = 11'd150;     // Initial gain start point
        i_rate_1      = 32'd15 << P; // Rate 1: 15.0 units per update
        i_duration_1  = 16'd20;      // Ramp 1 duration: 20 updates
        i_rate_2      = 32'd25 << P; // Rate 2: 25.0 units per update
        i_duration_2  = 16'd15;      // Ramp 2 duration: 15 updates
        i_dac_min     = 10'd100;
        i_dac_max     = 10'd400;     // DAC1 ceiling is 400, then DAC2 begins
        i_dac_sync    = 1'b1;

        @(posedge dac_clk);
        i_dac_sync    = 1'b0;

        repeat (200) begin
            @(posedge dac_clk);
            if (o_dac_data_vld) begin
                $display("[TB] Seq Step: State=%d | DAC1=%d | DAC2=%d | SPI1_CS_N=%b, SPI2_CS_N=%b", 
                         uut_vrc.state, o_dac1, o_dac2, o_sync1_n, o_sync2_n);
            end
        end
        $display("[TB] Test 2 Finished. Final Outputs -> DAC1: %d, DAC2: %d", o_dac1, o_dac2);

        // =====================================================================
        // TEST 3: Parallel/Equal Mode (i_vrc_type = 2'b10)
        // Expected behavior: Both DACs share the gain divided by 2
        // =====================================================================
        $display("[TB] Starting Test 3: Parallel/Equal Mode (2'b10)...");
        @(posedge dac_clk);
        i_vrc_type    = 2'b10;
        i_dac_div     = 8'd1;        // Update every clock cycle
        i_start_delay = 16'd5;       // 5-clock wait period
        i_init_gain   = 11'd300;     // Initial gain 300 / 2 = 150 code
        i_rate_1      = 32'd20 << P; // Rate 1: 20.0 units (shared rate = 10.0 units/clock)
        i_duration_1  = 16'd30;      // 30 clock steps
        i_rate_2      = 32'd0;       // Disabled ramp 2
        i_duration_2  = 16'd0;
        i_dac_min     = 10'd100;
        i_dac_max     = 10'd400;     // DAC ceiling limit
        i_dac_sync    = 1'b1;

        @(posedge dac_clk);
        i_dac_sync    = 1'b0;

        repeat (100) begin
            @(posedge dac_clk);
            if (o_dac_data_vld) begin
                $display("[TB] Par Step: State=%d | DAC1=%d | DAC2=%d | SPI1_CS_N=%b, SPI2_CS_N=%b", 
                         uut_vrc.state, o_dac1, o_dac2, o_sync1_n, o_sync2_n);
            end
        end
        $display("[TB] Test 3 Finished. Final Outputs -> DAC1: %d, DAC2: %d", o_dac1, o_dac2);

        // Allow final transmission cycles to finish before exit
        #1000;
        $display("[TB] Simulation completed successfully!");
        $finish;
    end

endmodule