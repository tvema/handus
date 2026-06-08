// src/adc_latch_param.v

`timescale 1ns / 1ps

module adc_latch_param (
    input             adc_clk,        // Входная тактовая частота 65MHz (без i_)
    input             adc_rst_n,      // Синхронизированный сброс для домена adc_clk (без i_)
    input             i_adc_sync,     // Сигнал внешней синхронизации запуска в домене adc_clk
    
    // Интерфейс команд от модуля param
    input             i_cmd_val,      // Флаг валидности команды
    input      [31:0] i_cmd_addr,     // Адрес команды
    input      [31:0] i_cmd_data,     // Данные команды
    
    // Выходные параметры для модуля ascan
    output reg [15:0] o_n_samples,    // Количество собираемых 12-битных отсчетов (подключается к i_n_samples в ascan)
    output reg [7:0]  o_accum,        // Параметр "накопление" (8-битное значение)
    output reg [3:0]  o_accum_type,   // Параметр "тип накопления" (4-битное значение)
    output reg [15:0] o_delay_time    // Время задержки (16-битное значение)
);

    // Теневые регистры для хранения принятых параметров до прихода i_adc_sync
    reg [15:0] shadow_n_samples;
    reg [7:0]  shadow_accum;
    reg [3:0]  shadow_accum_type;
    reg [15:0] shadow_delay_time;

    // Декодирование команд на частоте adc_clk
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            shadow_n_samples  <= 16'd0;
            shadow_accum      <= 8'd0;
            shadow_accum_type <= 4'd0;
            shadow_delay_time <= 16'd0;
        end else begin
            if (i_cmd_val) begin
                // Проверяем, что команда предназначена для домена adc_clk (старший байт адреса == 2)
                if (i_cmd_addr[31:24] == 8'd2) begin
                    case (i_cmd_addr[23:16])
                        8'd1: begin
                            // Адрес 1: Количество собираемых отсчетов (12-битных слов) для модуля ascan
                            shadow_n_samples <= i_cmd_data[15:0];
                        end
                        8'd2: begin
                            // Адрес 2: Параметр накопления
                            shadow_accum <= i_cmd_data[7:0];
                        end
                        8'd3: begin
                            // Адрес 3: Тип накопления (4-битное значение)
                            shadow_accum_type <= i_cmd_data[3:0];
                        end
                        8'd4: begin
                            // Адрес 4: Время задержки (16-битное значение)
                            shadow_delay_time <= i_cmd_data[15:0];
                        end
                        // Резерв для других параметров на частоте adc_clk
                        default: ;
                    endcase
                end
            end
        end
    end

    // Защёлкивание параметров в активные регистры по сигналу i_adc_sync
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            o_n_samples  <= 16'd0;
            o_accum      <= 8'd0;
            o_accum_type <= 4'd0;
            o_delay_time <= 16'd0;
        end else begin
            if (i_adc_sync) begin
                o_n_samples  <= shadow_n_samples;
                o_accum      <= shadow_accum;
                o_accum_type <= shadow_accum_type;
                o_delay_time <= shadow_delay_time;
            end
        end
    end

endmodule