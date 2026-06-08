`timescale 1ns / 1ps

module decimator_tb;

    // Parameters
    localparam CLK_PERIOD = 15.385; // ~65 MHz (1/65MHz = 15.3846 ns)

    // Signals
    reg                     clk;
    reg                     rst_n;
    reg                     i_sync;
    reg                     i_active;
    reg                     i_last;
    reg [7:0]               i_accum;
    reg [3:0]               i_accum_type;
    reg signed [11:0]       i_data;
    
    wire signed [11:0]      o_data;
    wire                    o_vld;

    // Instantiate Unit Under Test (UUT)
    ascan_decimator uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_sync       (i_sync),
        .i_active     (i_active),
        .i_last       (i_last),
        .i_accum      (i_accum),
        .i_accum_type (i_accum_type),
        .i_data       (i_data),
        .o_data       (o_data),
        .o_vld        (o_vld)
    );

    // Clock generator (65 MHz)
    always begin
        clk = 1'b0;
        #(CLK_PERIOD / 2.0);
        clk = 1'b1;
        #(CLK_PERIOD / 2.0);
    end

    // Helper task to reset the design
    task reset_system;
        begin
            rst_n        = 1'b0;
            i_sync       = 1'b0;
            i_active     = 1'b0;
            i_last       = 1'b0;
            i_accum      = 8'd4;
            i_accum_type = 4'd1;
            i_data       = 12'd0;
            #(CLK_PERIOD * 5);
            @(posedge clk);
            #1;
            rst_n        = 1'b1;
            #(CLK_PERIOD * 2);
        end
    endtask

    // Helper task to send a block of input samples
    task send_packet(
        input [7:0] accum,
        input [3:0] accum_type,
        input integer length,
        input integer pattern_type // 0: increment, 1: alternating, 2: random, 3: custom test
    );
        integer i;
        reg signed [11:0] val;
        begin
            $display("[TB] Starting transmission: Accum=%d, Type=%d, Length=%d, Pattern=%d", accum, accum_type, length, pattern_type);
            
            @(posedge clk);
            #1;
            i_accum      = accum;
            i_accum_type = accum_type;
            i_sync       = 1'b1;
            i_active     = 1'b1;
            i_last       = 1'b0;
            
            // First data sample along with i_sync pulse
            case (pattern_type)
                0: i_data = 12'd10;
                1: i_data = -12'd10;
                2: i_data = $random % 2048;
                default: i_data = 12'd5;
            endcase
            
            @(posedge clk);
            #1;
            i_sync = 1'b0; // sync is only active for 1 clock cycle

            for (i = 1; i < length; i = i + 1) begin
                case (pattern_type)
                    0: begin
                        // Incremental signed values with alternating signs
                        val = i * 10;
                        if (i % 2 == 1) val = -val;
                        i_data = val;
                    end
                    1: begin
                        // Alternating large positive/negative values
                        if (i % 2 == 0) i_data = 12'd1000;
                        else i_data = -12'd1500;
                    end
                    2: begin
                        // Random signed 12-bit values
                        i_data = $random % 2048;
                    end
                    3: begin
                        // Custom repeating sequence for predictable calculations
                        if (i % 4 == 0)      i_data = 12'd100;
                        else if (i % 4 == 1) i_data = -12'd200;
                        else if (i % 4 == 2) i_data = 12'd50;
                        else                 i_data = -12'd300;
                    end
                    default: i_data = 12'd0;
                endcase

                if (i == length - 1) begin
                    i_last = 1'b1;
                end
                
                @(posedge clk);
                #1;
            end

            i_active = 1'b0;
            i_last   = 1'b0;
            i_data   = 12'd0;
            
            // Wait for processing pipeline to flush
            #(CLK_PERIOD * 10);
        end
    endtask

    // Output Monitor
    always @(posedge clk) begin
        if (o_vld) begin
            $display("[MON] @%t: Valid Out o_data = %d (Hex: %h)", $time, o_data, o_data);
        end
    end
    
    // Main Test Sequence
    initial begin
        // Waveform dumping
        $dumpfile("decimator_tb.vcd");
        $dumpvars(0, decimator_tb);

        $display("[TB] Starting testbench for ascan_decimator...");
        
        reset_system();

        // --- TEST CASE 1: AccumType = 1 (Max by magnitude with original sign) ---
        // Accum factor = 4. 12 samples (expects 3 outputs).
        $display("\n--- TEST CASE 1: Max Absolute Value with Sign (Accum = 4, Type = 1) ---");
        send_packet(8'd4, 4'd1, 12, 3);

        // --- TEST CASE 2: AccumType = 2 (Average of Absolute Values) ---
        // Accum factor = 4. 8 samples (expects 2 outputs).
        $display("\n--- TEST CASE 2: Average of Absolute Values (Accum = 4, Type = 2) ---");
        send_packet(8'd4, 4'd2, 8, 3);

        // --- TEST CASE 3: AccumType = 3 (Max Absolute Value Unsigned) ---
        // Accum factor = 4. 8 samples.
        $display("\n--- TEST CASE 3: Max Absolute Value Unsigned (Accum = 4, Type = 3) ---");
        send_packet(8'd4, 4'd3, 8, 3);

        // --- TEST CASE 4: Accum factor = 8 with random data ---
        $display("\n--- TEST CASE 4: Accum = 8, Type = 1 (Random Data) ---");
        send_packet(8'd8, 4'd1, 16, 2);

        // --- TEST CASE 5: Accum factor = 1 (Pass-through mode) ---
        $display("\n--- TEST CASE 5: Accum = 1, Type = 1 (Pass-through) ---");
        send_packet(8'd1, 4'd1, 5, 0);

        // --- TEST CASE 6: Incomplete packet check with i_last ---
        // Accum = 5, packet length = 8 (not multiple of 5).
        $display("\n--- TEST CASE 6: Boundary check with i_last (Accum = 5, Type = 1) ---");
        send_packet(8'd5, 4'd1, 8, 0);

        $display("\n[TB] All tests finished!");
        $finish;
    end

endmodule