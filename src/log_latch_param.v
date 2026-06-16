// =========================================================================
// Module: log_latch_param
// Description: Decodes and latches configuration parameters for the log module
//              in the log_clk domain (25 MHz). Uses shadow registers to
//              safely update active values only upon receiving i_log_sync,
//              ensuring glitch-free pipeline parameters during active capture.
//              Default parameters are sourced from "def_param.h".
// =========================================================================

`timescale 1ns / 1ps

// Подключение дефолтных параметров проекта
`include "def_param.h"

module log_latch_param (
    // Clock and Reset (log_clk domain)
    input  wire        log_clk,         // log_clk: 25MHz
    input  wire        log_rst_n,       // Reset synchronized to log_clk (active low)

    // Command interface from param module (log_clk domain)
    input  wire        i_cmd_vld,       // Command valid flag
    input  wire [31:0] i_cmd_addr,      // Command address (high byte [23:16] == 3 for log_clk domain)
    input  wire [31:0] i_cmd_data,      // Command data (argument)

    // Sync signal to transfer shadow parameters to active outputs
    input  wire        i_log_sync,      // Latching trigger synchronized to log_clk

    // Output parameters for the log.v module
    output reg  [15:0] o_n_samples,     // Total raw samples to capture
    output reg  [7:0]  o_accum,         // Accumulation decimation rate
    output reg  [3:0]  o_accum_type,    // 1 = Peak detector, 2 = Integrator/Average
    output reg  [3:0]  o_trans_meth,    // 1 = >>2, 2 = Saturation, 3 = >>1 + Saturation
    output reg  [15:0] o_skip_ticks     // Startup delay in log_clk cycles
);

    // Command Address Definitions (for Domain 3)
    localparam CMD_N_SAMPLES  = 8'h01;  // Number of samples to capture
    localparam CMD_ACCUM      = 8'h02;  // Accumulation factor
    localparam CMD_ACCUM_TYPE = 8'h03;  // Accumulation type (Peak/Average)
    localparam CMD_TRANS_METH = 8'h04;  // Transmission/Compression method
    localparam CMD_SKIP_TICKS = 8'h05;  // Startup skip ticks (delay)

    // Shadow/holding registers to store parameters before the sync pulse
    reg [15:0] shadow_n_samples;
    reg [7:0]  shadow_accum;
    reg [3:0]  shadow_accum_type;
    reg [3:0]  shadow_trans_meth;
    reg [15:0] shadow_skip_ticks;

    // 1. Command Decoding and Shadow Register Update
    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            // Default/safe startup parameters from def_param.h
            shadow_n_samples  <= `INIT_LOG_N_SAMPLES;
            shadow_accum      <= `INIT_LOG_ACCUM;
            shadow_accum_type <= `INIT_LOG_ACCUM_TYPE;
            shadow_trans_meth <= `INIT_LOG_TRANS_METH;
            shadow_skip_ticks <= `INIT_LOG_SKIP_TICKS;
        end else begin
            if (i_cmd_vld && (i_cmd_addr[23:16] == 8'd3)) begin
                case (i_cmd_addr[7:0])
                    CMD_N_SAMPLES:  shadow_n_samples  <= i_cmd_data[15:0];
                    CMD_ACCUM:      shadow_accum      <= i_cmd_data[7:0];
                    CMD_ACCUM_TYPE: shadow_accum_type <= i_cmd_data[3:0];
                    CMD_TRANS_METH: shadow_trans_meth <= i_cmd_data[3:0];
                    CMD_SKIP_TICKS: shadow_skip_ticks <= i_cmd_data[15:0];
                    default: ; // Ignore other addresses
                endcase
            end
        end
    end

    // 2. Active Parameter Update on Sync Trigger
    always @(posedge log_clk or negedge log_rst_n) begin
        if (!log_rst_n) begin
            // Reset active outputs to defaults from def_param.h
            o_n_samples  <= `INIT_LOG_N_SAMPLES;
            o_accum      <= `INIT_LOG_ACCUM;
            o_accum_type <= `INIT_LOG_ACCUM_TYPE;
            o_trans_meth <= `INIT_LOG_TRANS_METH;
            o_skip_ticks <= `INIT_LOG_SKIP_TICKS;
        end else begin
            if (i_log_sync) begin
                o_n_samples  <= shadow_n_samples;
                o_accum      <= shadow_accum;
                o_accum_type <= shadow_accum_type;
                o_trans_meth <= shadow_trans_meth;
                o_skip_ticks <= shadow_skip_ticks;
            end
        end
    end

endmodule