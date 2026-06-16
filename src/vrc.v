// src/vrc.v

`timescale 1ns / 1ps

module vrc #(
    parameter P = 16 // Количество дробных бит для вычислений с фиксированной точкой
) (
    // Тактовый сигнал и сброс (согласно глобальным правилам проекта)
    input  wire        dac_clk,          // dac_clk: 50MHz
    input  wire        dac_rst_n,        // Синхронизированный асинхронный сброс (активный низкий)

    // Входной сигнал синхронизации
    input  wire        i_dac_sync,       // Импульс запуска (синхронизирован в dac_clk)

    // Входные конфигурационные параметры
    input  wire [1:0]  i_vrc_type,       // 00 - Константный, 01 - Последовательный, 10 - Одинаковый/Параллельный
    input  wire [7:0]  i_dac_div,        // Делитель частоты обновления ЦАП (интервал изменения шага)
    input  wire [15:0] i_start_delay,    // Время задержки начала нарастания (в тактах dac_clk)
    input  wire [10:0] i_init_gain,      // Начальное значение усиления
    input  wire [31:0] i_rate_1,         // Скорость нарастания 1 (float, умноженный на 2^P)
    input  wire [15:0] i_duration_1,     // Время нарастания 1 (количество шагов обновления)
    input  wire [31:0] i_rate_2,         // Скорость нарастания 2 (float, умноженный на 2^P)
    input  wire [15:0] i_duration_2,     // Время нарастания 2 (количество шагов обновления)
    input  wire [9:0]  i_dac_min,        // Минимальное ограничение кода ЦАП
    input  wire [9:0]  i_dac_max,        // Максимальное ограничение кода ЦАП

    // Сигнал готовности приемника dac_spi
    input  wire        i_dac_rdy,        // Готовность dac_spi к приему новых данных (очищает o_dac_data_vld)

    // Выходной интерфейс управления для dac_spi
    output reg         o_dac_vld,        // Высокий уровень в течение всего времени нарастания сигнала ВРЧ
    output reg         o_dac_data_vld,   // Строб валидности данных для защелкивания в dac_spi (работает по рукопожатию)
    output reg  [9:0]  o_dac1,           // Выходной код для ЦАП 1 (10-бит)
    output reg  [9:0]  o_dac2            // Выходной код для ЦАП 2 (10-бит)
);

    // Состояния конечного автомата (FSM)
    localparam [2:0] STATE_IDLE   = 3'd0;
    localparam [2:0] STATE_DELAY  = 3'd1;
    localparam [2:0] STATE_RAMP1  = 3'd2;
    localparam [2:0] STATE_RAMP2  = 3'd3;
    localparam [2:0] STATE_DONE   = 3'd4;

    reg [2:0]  state;
    reg [15:0] cnt;
    
    // Аккумулятор: 32 целых бита + P дробных бит для точного сложения скоростей
    reg [31+P:0] gain_accum;
    
    // Выделение целой части значения накопленного усиления
    wire [31:0] gain_int = gain_accum[31+P : P];

    // Счетчик делителя частоты для регулировки интервала нарастания
    reg [7:0] div_cnt;
    wire      tick = (i_dac_div <= 8'd1) ? 1'b1 : (div_cnt == i_dac_div - 8'd1);

    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            div_cnt <= 8'd0;
        end else begin
            if (i_dac_sync) begin
                div_cnt <= 8'd0;
            end else if (state == STATE_RAMP1 || state == STATE_RAMP2) begin
                if (tick) begin
                    div_cnt <= 8'd0;
                end else begin
                    div_cnt <= div_cnt + 8'd1;
                end
            end else begin
                div_cnt <= 8'd0;
            end
        end
    end

    // Конечный автомат управления профилем ВРЧ
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            state      <= STATE_IDLE;
            cnt        <= 16'd0;
            gain_accum <= {(32+P){1'b0}};
        end else begin
            if (i_dac_sync) begin
                // Инициализация аккумулятора начальным усилением со сдвигом на P бит
                gain_accum <= { {32{1'b0}}, i_init_gain } << P;
                
                if (i_vrc_type == 2'b00) begin
                    state <= STATE_IDLE;
                end else if (i_start_delay > 0) begin
                    cnt   <= i_start_delay;
                    state <= STATE_DELAY;
                end else if (i_duration_1 > 0) begin
                    cnt   <= i_duration_1;
                    state <= STATE_RAMP1;
                end else if (i_duration_2 > 0) begin
                    cnt   <= i_duration_2;
                    state <= STATE_RAMP2;
                end else begin
                    state <= STATE_DONE;
                end
            end else begin
                case (state)
                    STATE_IDLE: begin
                        // Ожидание i_dac_sync
                    end

                    STATE_DELAY: begin
                        // Задержка отсчитывается по тактам dac_clk
                        if (cnt > 16'd1) begin
                            cnt <= cnt - 16'd1;
                        end else begin
                            if (i_duration_1 > 0) begin
                                cnt   <= i_duration_1;
                                state <= STATE_RAMP1;
                            end else if (i_duration_2 > 0) begin
                                cnt   <= i_duration_2;
                                state <= STATE_RAMP2;
                            end else begin
                                state <= STATE_DONE;
                            end
                        end
                    end

                    STATE_RAMP1: begin
                        if (tick) begin
                            // Шаг инкремента на скорость нарастания 1
                            gain_accum <= gain_accum + { {(P){1'b0}}, i_rate_1 };
                            if (cnt > 16'd1) begin
                                cnt <= cnt - 16'd1;
                            end else begin
                                if (i_duration_2 > 0) begin
                                    cnt   <= i_duration_2;
                                    state <= STATE_RAMP2;
                                end else begin
                                    state <= STATE_DONE;
                                end
                            end
                        end
                    end

                    STATE_RAMP2: begin
                        if (tick) begin
                            // Шаг инкремента на скорость нарастания 2
                            gain_accum <= gain_accum + { {(P){1'b0}}, i_rate_2 };
                            if (cnt > 16'd1) begin
                                cnt <= cnt - 16'd1;
                            end else begin
                                state <= STATE_DONE;
                            end
                        end
                    end

                    STATE_DONE: begin
                        // Удержание конечного значения усиления до следующего цикла
                    end

                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end

    // Комбинаторная логика распределения усиления на каналы ЦАП
    reg [9:0]  dac1_next;
    reg [9:0]  dac2_next;
    reg [31:0] excess_gain;
    reg [31:0] shared_gain;

    always @(*) begin
        excess_gain = 32'd0;
        shared_gain = 32'd0;
        dac1_next   = i_dac_min;
        dac2_next   = i_dac_min;

        case (i_vrc_type)
            // ТИП 1 (2'b01): Последовательное регулирование
            // Сначала нарастает DAC1 до максимума, затем начинает нарастать DAC2.
            2'b01: begin
                if (gain_int <= i_dac_max) begin
                    dac1_next = (gain_int < i_dac_min) ? i_dac_min : gain_int[9:0];
                    dac2_next = i_dac_min;
                end else begin
                    dac1_next   = i_dac_max;
                    excess_gain = gain_int - i_dac_max;
                    if (excess_gain + i_dac_min >= i_dac_max) begin
                        dac2_next = i_dac_max;
                    end else begin
                        dac2_next = i_dac_min + excess_gain[9:0];
                    end
                end
            end

            // ТИП 2 (2'b10): Одинаковое / Параллельное регулирование
            // На оба ЦАПа выдается одинаковое значение (усиление делится на 2)
            2'b10: begin
                shared_gain = gain_int >> 1;
                if (shared_gain < i_dac_min) begin
                    dac1_next = i_dac_min;
                    dac2_next = i_dac_min;
                end else if (shared_gain > i_dac_max) begin
                    dac1_next = i_dac_max;
                    dac2_next = i_dac_max;
                end else begin
                    dac1_next = shared_gain[9:0];
                    dac2_next = shared_gain[9:0];
                end
            end

            // Режим байпаса / Постоянного значения (2'b00)
            default: begin
                if (i_init_gain < i_dac_min) begin
                    dac1_next = i_dac_min;
                    dac2_next = i_dac_min;
                end else if (i_init_gain > i_dac_max) begin
                    dac1_next = i_dac_max;
                    dac2_next = i_dac_max;
                end else begin
                    dac1_next = i_init_gain[9:0];
                    dac2_next = i_init_gain[9:0];
                end
            end
        endcase
    end

    // Выходные регистры для фильтрации глитчей и формирования сигналов управления dac_spi
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            o_dac1         <= 10'd0;
            o_dac2         <= 10'd0;
            o_dac_vld      <= 1'b0;
            o_dac_data_vld <= 1'b0;
        end else begin
            o_dac1 <= dac1_next;
            o_dac2 <= dac2_next;
            
            // Сигнал огибающей активности: высокий в течении времени пока идет нарастание (RAMP1, RAMP2)
            o_dac_vld <= (state == STATE_RAMP1 || state == STATE_RAMP2);
            
            // Рукопожатие: Выставляем o_dac_data_vld при обновлении данных,
            // сбрасываем при получении подтверждения готовности (i_dac_rdy), если в этот же момент нет нового шага.
            if (i_dac_sync) begin
                // Запуск при инициализации нового профиля
                o_dac_data_vld <= 1'b1;
            end else if ((state == STATE_RAMP1 || state == STATE_RAMP2) && tick) begin
                // Запуск на каждом шаге деления частоты при нарастании
                o_dac_data_vld <= 1'b1;
            end else if (i_dac_rdy) begin
                // Данные были успешно защёлкнуты/отправлены dac_spi
                o_dac_data_vld <= 1'b0;
            end
        end
    end

endmodule