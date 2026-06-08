`timescale 1ns / 1ps

module ascan_tb;

    // Parameters
    parameter ADDR_WIDTH = 11;

    // Inputs (Regs)
    reg                     sys_clk;
    reg                     sys_rst_n;
    reg                     i_out_rdy;
    reg                     adc_clk;
    reg                     adc_rst_n;
    reg [11:0]              i_in_data;
    reg                     i_adc_sync;
    reg [15:0]              i_n_samples;
    reg [7:0]               i_accum;
    reg [3:0]               i_accum_type;

    // Outputs (Wires)
    wire                    o_data_ready;
    wire [15:0]             o_out_size;
    wire [31:0]             o_out_data;
    wire                    o_out_vld;

    // Instantiate Unit Under Test (UUT)
    ascan #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .o_data_ready(o_data_ready),
        .o_out_size(o_out_size),
        .o_out_data(o_out_data),
        .o_out_vld(o_out_vld),
        .i_out_rdy(i_out_rdy),
        .adc_clk(adc_clk),
        .adc_rst_n(adc_rst_n),
        .i_in_data(i_in_data),
        .i_adc_sync(i_adc_sync),
        .i_n_samples(i_n_samples),
        .i_accum(i_accum),
        .i_accum_type(i_accum_type)
    );

    // Clock generation
    // sys_clk: 80 MHz -> Period 12.5 ns (6.25 ns half-period)
    initial sys_clk = 0;
    always #6.25 sys_clk = ~sys_clk;

    // adc_clk: 65 MHz -> Period 15.3846 ns (7.6923 ns half-period)
    initial adc_clk = 0;
    always #7.692 adc_clk = ~adc_clk;

    // ADC data generation: incrementing counter simulation of the input stream
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            i_in_data <= 12'sd0;
        end else begin
            i_in_data <= i_in_data + 1'b1;
        end
    end

    // Global Watchdog Timer to prevent infinite simulation hangs
    initial begin
        #500000; // Ограничение по времени 50 микросекунд
        $display("[TB ERROR] Simulation timeout reached! Force terminating.");
        $finish;
    end

    // Simulation Flow
    initial begin
        $dumpfile("ascan_tb.vcd");
        $dumpvars(0, ascan_tb);

        // Initial state of controls
        sys_rst_n = 0;
        adc_rst_n = 0;
        i_out_rdy = 0;
        i_adc_sync = 0;
        i_n_samples = 16'd32; // Configure to capture 32 samples
        i_accum = 8'd4;
        i_accum_type = 4'd1;

        // Wait and release reset asynchronously
        #100;
        sys_rst_n = 1;
        adc_rst_n = 1;
        #100;

        // --- TEST CASE 1: Single Acquisition & Readout ---
        $display("[TB] --- Starting Test Case 1: Single Buffer Acquisition ---");
        
        // Trigger acquisition in adc_clk domain
        @(posedge adc_clk);
        #1;
        i_adc_sync = 1;
        @(posedge adc_clk);
        #1;
        i_adc_sync = 0;

        // Wait for buffer ready flag in sys_clk domain
        @(posedge sys_clk);
        while (!o_data_ready) begin
            @(posedge sys_clk);
        end
        $display("[TB] Buffer ready. Size = %d words.", o_out_size);

        // Enable receiver
        i_out_rdy = 1;

        // Read out several words
        repeat (5) begin
            @(posedge sys_clk);
            while (!o_out_vld) @(posedge sys_clk);
            $display("[TB] Read word: 0x%h", o_out_data);
        end

        // Apply receiver backpressure (pause reading to verify handshaking)
        $display("[TB] Applying backpressure (i_out_rdy = 0)");
        i_out_rdy = 0;
        #80;
        i_out_rdy = 1;
        $display("[TB] Backpressure released");

        // Finish reading first buffer
        while (o_data_ready) begin
            @(posedge sys_clk);
            if (o_out_vld && i_out_rdy) begin
                $display("[TB] Read word: 0x%h", o_out_data);
            end
        end
        i_out_rdy = 0;
        $display("[TB] Test Case 1 completed.");
        #200;

        // --- TEST CASE 2: Butterfly Buffer Mode (Simultaneous Capture & Read) ---
        $display("[TB] --- Starting Test Case 2: Butterfly Mode ---");
        
        // Trigger first buffer acquisition
        @(posedge adc_clk);
        #1;
        i_adc_sync = 1;
        @(posedge adc_clk);
        #1;
        i_adc_sync = 0;

        // Wait for first buffer to be filled
        @(posedge sys_clk);
        while (!o_data_ready) @(posedge sys_clk);
        $display("[TB] First buffer ready. Starting readout and triggering second acquisition...");

        // Start reading out first buffer
        i_out_rdy = 1;

        // Simultaneously trigger second acquisition to write into the secondary buffer
        @(posedge adc_clk);
        #1;
        i_adc_sync = 1;
        @(posedge adc_clk);
        #1;
        i_adc_sync = 0;

        // Run simulation to observe simultaneous reading of buffer A and writing of buffer B
        #1000;

        $display("[TB] Simulation completed successfully!");
        $finish;
    end

endmodule