`timescale 1ns / 1ps

module main_tb;

    // Auto-generated Testbench for main_tb
    // Add your signals and instantiation here
    
    initial begin
`ifdef VCD_FILE
        $dumpfile(`VCD_FILE);
`else
        $dumpfile("main_tb.vcd");
`endif
        $dumpvars(0, main_tb);
        
        // Simulation logic
        #100;
        
        $finish;
    end

endmodule
