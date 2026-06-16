// src/pulse_latch_param.v

`default_nettype none

module pulse_latch_param (
    // Входной тактовый сигнал и сброс для домена hi_clk
    input  wire        hi_clk,
    input  wire        hi_rst_n,

    // Входящий сигнал синхронизации в домене hi_clk
    input  wire        i_hi_sync,

    // Входной поток команд от модуля param (в домене hi_clk)
    input  wire        i_cmd_val,
    input  wire [31:0] i_cmd_addr,
    input  wire [31:0] i_cmd_data,

    // Выходные защелкнутые параметры для использования в домене hi_clk
    output reg  [15:0] o_charge_time,
    output reg  [15:0] o_transmit_time,
    output reg  [7:0]  o_pulse_width
);

    // Временные регистры для промежуточного сохранения параметров до импульса синхронизации
    reg [15:0] temp_charge_time;
    reg [15:0] temp_transmit_time;
    reg [7:0]  temp_pulse_width;

    //--------------------------------------------------------------------------
    // Декодирование входящих команд и запись во временные регистры
    //--------------------------------------------------------------------------
    always @(posedge hi_clk or negedge hi_rst_n) begin
        if (!hi_rst_n) begin
            temp_charge_time   <= 16'd0;
            temp_transmit_time <= 16'd0;
            temp_pulse_width   <= 8'd0;
        end else begin
            if (i_cmd_val) begin
                case (i_cmd_addr[23:16])
                    8'd1: temp_charge_time   <= i_cmd_data[15:0];
                    8'd2: temp_transmit_time <= i_cmd_data[15:0];
                    8'd3: temp_pulse_width   <= i_cmd_data[7:0];
                    default: ; // Игнорируем команды с другими адресами назначения
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    // Защелкивание параметров в выходные регистры по сигналу i_hi_sync
    //--------------------------------------------------------------------------
    always @(posedge hi_clk or negedge hi_rst_n) begin
        if (!hi_rst_n) begin
            o_charge_time   <= 16'd0;
            o_transmit_time <= 16'd0;
            o_pulse_width   <= 8'd0;
        end else begin
            if (i_hi_sync) begin
                o_charge_time   <= temp_charge_time;
                o_transmit_time <= temp_transmit_time;
                o_pulse_width   <= temp_pulse_width;
            end
        end
    end

endmodule

`default_nettype wire