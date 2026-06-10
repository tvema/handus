// src/vrc_param_latch.v

`default_nettype none

module vrc_param_latch (
    // Тактовая частота и сброс (домен dac_clk)
    input  wire        dac_clk,          // dac_clk: 50MHz
    input  wire        dac_rst_n,        // Синхронизированный асинхронный сброс (активный низкий)

    // Сигнал внешней синхронизации для обновления рабочих регистров
    input  wire        i_dac_sync,       // Импульс запуска (синхронизирован в dac_clk)

    // Входной поток команд от модуля param (на частоте dac_clk)
    input  wire        i_cmd_val,
    input  wire [31:0] i_cmd_addr,
    input  wire [31:0] i_cmd_data,

    // Выходные сконфигурированные параметры для модуля vrc
    output reg  [1:0]  o_vrc_type,       // Тип ВРЧ
    output reg  [7:0]  o_dac_div,        // Делитель частоты обновления ЦАП
    output reg  [15:0] o_start_delay,    // Время задержки начала нарастания
    output reg  [10:0] o_init_gain,      // Начальное значение усиления
    output reg  [31:0] o_rate_1,         // Скорость нарастания 1
    output reg  [15:0] o_duration_1,     // Время нарастания 1
    output reg  [31:0] o_rate_2,         // Скорость нарастания 2
    output reg  [15:0] o_duration_2,     // Время нарастания 2
    output reg  [9:0]  o_dac_min,        // Минимальное ограничение кода ЦАП
    output reg  [9:0]  o_dac_max         // Максимальное ограничение кода ЦАП
);

    //--------------------------------------------------------------------------
    // Промежуточные (Holding) регистры для хранения параметров до прихода i_dac_sync
    //--------------------------------------------------------------------------
    reg [1:0]  hold_vrc_type;
    reg [7:0]  hold_dac_div;
    reg [15:0] hold_start_delay;
    reg [10:0] hold_init_gain;
    reg [31:0] hold_rate_1;
    reg [15:0] hold_duration_1;
    reg [31:0] hold_rate_2;
    reg [15:0] hold_duration_2;
    reg [9:0]  hold_dac_min;
    reg [9:0]  hold_dac_max;

    //--------------------------------------------------------------------------
    // Запись в промежуточные регистры по командам из шины param
    //--------------------------------------------------------------------------
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            hold_vrc_type    <= 2'b00;
            hold_dac_div     <= 8'd1;
            hold_start_delay <= 16'd0;
            hold_init_gain   <= 11'd0;
            hold_rate_1      <= 32'd0;
            hold_duration_1  <= 16'd0;
            hold_rate_2      <= 32'd0;
            hold_duration_2  <= 16'd0;
            hold_dac_min     <= 10'd0;
            hold_dac_max     <= 10'd1023; // По умолчанию максимальный диапазон 10-бит ЦАП
        end else if (i_cmd_val) begin
            // Декодируем только адреса нашего домена (04)
            if (i_cmd_addr[31:24] == 8'h04) begin
                case (i_cmd_addr[7:0])
                    8'h01: begin
                        hold_vrc_type <= i_cmd_data[1:0];
                        hold_dac_div  <= i_cmd_data[15:8];
                    end
                    8'h02: hold_start_delay <= i_cmd_data[15:0];
                    8'h03: hold_init_gain   <= i_cmd_data[10:0];
                    8'h04: hold_rate_1      <= i_cmd_data[31:0];
                    8'h05: hold_duration_1  <= i_cmd_data[15:0];
                    8'h06: hold_rate_2      <= i_cmd_data[31:0];
                    8'h07: hold_duration_2  <= i_cmd_data[15:0];
                    8'h08: begin
                        hold_dac_min <= i_cmd_data[9:0];
                        hold_dac_max <= i_cmd_data[25:16];
                    end
                    default: ; // Игнорируем неописанные адреса
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    // Перенос параметров в активные рабочие регистры по сигналу i_dac_sync
    //--------------------------------------------------------------------------
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            o_vrc_type    <= 2'b00;
            o_dac_div     <= 8'd1;
            o_start_delay <= 16'd0;
            o_init_gain   <= 11'd0;
            o_rate_1      <= 32'd0;
            o_duration_1  <= 16'd0;
            o_rate_2      <= 32'd0;
            o_duration_2  <= 16'd0;
            o_dac_min     <= 10'd0;
            o_dac_max     <= 10'd1023;
        end else if (i_dac_sync) begin
            o_vrc_type    <= hold_vrc_type;
            o_dac_div     <= hold_dac_div;
            o_start_delay <= hold_start_delay;
            o_init_gain   <= hold_init_gain;
            o_rate_1      <= hold_rate_1;
            o_duration_1  <= hold_duration_1;
            o_rate_2      <= hold_rate_2;
            o_duration_2  <= hold_duration_2;
            o_dac_min     <= hold_dac_min;
            o_dac_max     <= hold_dac_max;
        end
    end

endmodule

`default_nettype wire