`timescale 1ns / 1ps

module main_tb;

    // -------------------------------------------------------------------------
    // Clock & Reset Signals
    // -------------------------------------------------------------------------
    reg sys_clk = 0;
    reg adc_clk = 0;
    reg log_clk = 0;
    reg dac_clk = 0;
    reg hi_clk  = 0;
    reg rst_n   = 0;

    // -------------------------------------------------------------------------
    // Clock Generation (All frequencies specified in Global Config)
    // -------------------------------------------------------------------------
    always #6.250  sys_clk = ~sys_clk; // sys_clk: 80MHz  (Period = 12.5ns)
    always #7.692  adc_clk = ~adc_clk; // adc_clk: 65MHz  (Period = 15.38ns)
    always #20.000 log_clk = ~log_clk; // log_clk: 25MHz  (Period = 40.0ns)
    always #10.000 dac_clk = ~dac_clk; // dac_clk: 50MHz  (Period = 20.0ns)
    always #2.000  hi_clk  = ~hi_clk;  // hi_clk:  250MHz (Period = 4.0ns)

    // -------------------------------------------------------------------------
    // UUT Port Signals
    // -------------------------------------------------------------------------
    reg         i_sys_sync;
    reg         i_cmd_val;
    reg  [31:0] i_cmd_addr;
    reg  [31:0] i_cmd_data;
    reg  [11:0] i_adc_data;
    reg  [9:0]  i_log_adc_data;

    wire [31:0] o_packet_data;
    wire        o_packet_vld;
    reg         i_packet_rdy;

    wire        o_packet_ready;
    wire [15:0] o_packet_size;

    wire        o_pulse_turn_on;
    wire        o_pulse_strike;

    wire        o_dac_vld;
    wire        o_dac_data_vld;
    wire [9:0]  o_dac1;
    wire [9:0]  o_dac2;
    reg         i_dac_rdy;

    // -------------------------------------------------------------------------
    // Unit Under Test (UUT) Instantiation
    // -------------------------------------------------------------------------
    main uut (
        .sys_clk         (sys_clk),
        .adc_clk         (adc_clk),
        .log_clk         (log_clk),
        .dac_clk         (dac_clk),
        .hi_clk          (hi_clk),
        .rst_n           (rst_n),
        .i_sys_sync      (i_sys_sync),
        .i_cmd_val       (i_cmd_val),
        .i_cmd_addr      (i_cmd_addr),
        .i_cmd_data      (i_cmd_data),
        .i_adc_data      (i_adc_data),
        .i_log_adc_data  (i_log_adc_data),
        .o_packet_data   (o_packet_data),
        .o_packet_vld    (o_packet_vld),
        .i_packet_rdy    (i_packet_rdy),
        .o_packet_ready  (o_packet_ready),
        .o_packet_size   (o_packet_size),
        .o_pulse_turn_on (o_pulse_turn_on),
        .o_pulse_strike  (o_pulse_strike),
        .o_dac_vld       (o_dac_vld),
        .o_dac_data_vld  (o_dac_data_vld),
        .o_dac1          (o_dac1),
        .o_dac2          (o_dac2),
        .i_dac_rdy       (i_dac_rdy)
    );

    // -------------------------------------------------------------------------
    // Input Stimulus Generators
    // -------------------------------------------------------------------------
    // ADC Domain raw mock signal (Counter)
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            i_adc_data <= 12'd2048; // Baseline midscale
        end else begin
            i_adc_data <= i_adc_data + 12'd1;
        end
    end

    // Log-ADC Domain raw mock signal
    always @(posedge log_clk or negedge rst_n) begin
        if (!rst_n) begin
            i_log_adc_data <= 10'd512;
        end else begin
            i_log_adc_data <= i_log_adc_data + 10'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    // Helper task to send commands to parameter hub (sys_clk domain)
    task send_cmd;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge sys_clk);
            i_cmd_addr <= addr;
            i_cmd_data <= data;
            i_cmd_val  <= 1'b1;
            @(posedge sys_clk);
            i_cmd_val  <= 1'b0;
            i_cmd_addr <= 32'd0;
            i_cmd_data <= 32'd0;
            @(posedge sys_clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Simulation Logic
    // -------------------------------------------------------------------------
    initial begin
`ifdef VCD_FILE
        $dumpfile(`VCD_FILE);
`else
        $dumpfile("main_tb.vcd");
`endif
        $dumpvars(0, main_tb);
        
        $display("================================================================");
        $display("                   STARTING TOP-LEVEL MAIN TB                   ");
        $display("================================================================");

        // Initial state of variables
        rst_n          = 1'b0;
        i_sys_sync     = 1'b0;
        i_cmd_val      = 1'b0;
        i_cmd_addr     = 32'd0;
        i_cmd_data     = 32'd0;
        i_packet_rdy   = 1'b1;
        i_dac_rdy      = 1'b1;

        // Apply Reset
        #100;
        rst_n = 1'b1;
        $display("[TB] Reset deasserted at %t", $realtime);
        #100;

        // -------------------------------------------------------------------------
        // Configure Submodules (Param Hub distribution)
        // -------------------------------------------------------------------------
        $display("[TB] Sending configuration parameter commands...");

        // 1. High-Voltage Pulse timing setup (Domain 5 - hi_clk)
        send_cmd(32'h05_01_00_00, 32'd10);  // Charge Time: 10 ticks
        send_cmd(32'h05_02_00_00, 32'd15);  // Transmit Time: 15 ticks
        send_cmd(32'h05_03_00_00, 32'd8);   // Strike Pulse Width: 8 ticks

        // 2. A-Scan parameter setup (Domain 2 - adc_clk)
        send_cmd(32'h02_01_00_00, 32'd32);  // Number of samples to accumulate: 32
        send_cmd(32'h02_02_00_00, 32'd5);   // skip_ticks (Delay limit): 5

        // 3. Log-Scan parameter setup (Domain 3 - log_clk)
        send_cmd(32'h03_01_00_00, 32'd16);  // Number of samples: 16
        send_cmd(32'h03_02_00_00, 32'd10);  // skip_ticks: 10

        // 4. VRC / DAC parameter setup (Domain 4 - dac_clk)
        send_cmd(32'h04_01_00_00, 32'd1);   // VRC Type Sequential: 1
        send_cmd(32'h04_02_00_00, 32'd150); // Min DAC: 150
        send_cmd(32'h04_03_00_00, 32'd950); // Max DAC: 950
        send_cmd(32'h04_04_00_00, 32'd12);  // Start Delay ticks: 12

        $display("[TB] Programming complete. Waiting for sync trigger...");
        #200;

        // -------------------------------------------------------------------------
        // Global Sync Pulse (Triggers cycle: Pulse -> VRC ramp -> ADC Capture)
        // -------------------------------------------------------------------------
        $display("[TB] Issuing sys_sync pulse.");
        @(posedge sys_clk);
        i_sys_sync <= 1'b1;
        @(posedge sys_clk);
        i_sys_sync <= 1'b0;

        // Run until the cycle begins and high power generation completes
        #2500;

        // Simulate packet sink downstream briefly going busy (Backpressure)
        $display("[TB] Inducing downstream packet backpressure (packet_rdy = 0)...");
        i_packet_rdy <= 1'b0;
        #300;
        i_packet_rdy <= 1'b1;
        $display("[TB] Backpressure cleared.");

        // Wait to finish the entire read cycle of A-scan and Log-scan packets
        #5000;

        $display("================================================================");
        $display("                    SIMULATION COMPLETED                        ");
        $display("================================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Monitoring Monitors
    // -------------------------------------------------------------------------
    // Pulse Generator Monitor
    reg last_turn_on = 0;
    reg last_strike  = 0;
    always @(posedge hi_clk) begin
        if (o_pulse_turn_on !== last_turn_on || o_pulse_strike !== last_strike) begin
            $display("[MON-PULSE] At %t | TurnOn: %b | Strike: %b", 
                     $realtime, o_pulse_turn_on, o_pulse_strike);
            last_turn_on <= o_pulse_turn_on;
            last_strike  <= o_pulse_strike;
        end
    end

    // VRC DAC Value Updates Monitor
    always @(posedge dac_clk) begin
        if (o_dac_vld) begin
            $display("[MON-VRC]   At %t | DAC1: %d | DAC2: %d | DataVld: %b", 
                     $realtime, o_dac1, o_dac2, o_dac_data_vld);
        end
    end

    // Packet Serializer Output Monitor
    always @(posedge sys_clk) begin
        if (o_packet_vld && i_packet_rdy) begin
            $display("[MON-PACK]  At %t | Out Word: 0x%h | Pkt Ready: %b | Size: %d", 
                     $realtime, o_packet_data, o_packet_ready, o_packet_size);
        end
    end

endmodule