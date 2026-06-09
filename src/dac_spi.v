`timescale 1ns / 1ps

module dac_spi #(
    // Старшие 4 бита кадра (DB15, DB14 - режим работы; DB13, DB12 - не используются/зарезервированы)
    // Возможные значения параметра DAC_OP_MODE:
    // 4'b0000 (4'h0) - Нормальный режим работы (Normal Operation) - по умолчанию.
    // 4'b0100 (4'h4) - Режим Power-Down: выход притянут к GND через резистор 1 кОм.
    // 4'b1000 (4'h8) - Режим Power-Down: выход притянут к GND через резистор 100 кОм.
    // 4'b1100 (4'hC) - Режим Power-Down: выход находится в высокоимпедансном состоянии (Hi-Z).
    parameter [3:0] DAC_OP_MODE = 4'b0000
)(
    // Clock & Reset (в соответствии с глобальными правилами проекта)
    input  wire        dac_clk,         // dac_clk: 50MHz (без префикса "i_")
    input  wire        dac_rst_n,       // dac_rst_n: синхронизированный сброс (без префикса "i_")

    // Интерфейс управления и данных
    input  wire        i_dac_sync,      // Импульс синхронизации для запуска цикла записи ЦАП (в домене dac_clk)
    input  wire [9:0]  i_dac_data,      // 10-битное входное значение для ЦАП
    input  wire        i_dac_data_vld,  // Строб валидности/защелкивания для i_dac_data

    // Аппаратный интерфейс ЦАП (SPI)
    output reg         o_dac_sclk,      // SPI Serial Clock (25 MHz = dac_clk / 2)
    output reg         o_dac_sdin,      // SPI Serial Data Input (SDIN/MOSI)
    output reg         o_dac_sync_n,    // SPI Frame Sync (SYNC_N / CS_N)

    // Выход статуса
    output reg         o_busy           // Высокий уровень во время активной передачи по SPI
);

    // Состояния конечного автомата (FSM)
    localparam STATE_IDLE = 1'b0;
    localparam STATE_TX   = 1'b1;

    reg        state;
    reg [5:0]  step_cnt;
    reg [9:0]  r_dac_data;
    reg [15:0] shift_reg;

    // 1. Защелкивание входящих данных по стробу валидности
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            r_dac_data <= 10'd0;
        end else if (i_dac_data_vld) begin
            r_dac_data <= i_dac_data;
        end
    end

    // 2. Конечный автомат передачи SPI
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            state        <= STATE_IDLE;
            step_cnt     <= 6'd0;
            shift_reg    <= 16'd0;
            o_dac_sclk   <= 1'b1;
            o_dac_sdin   <= 1'b0;
            o_dac_sync_n <= 1'b1;
            o_busy       <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    o_dac_sync_n <= 1'b1;
                    o_dac_sclk   <= 1'b1;
                    o_dac_sdin   <= 1'b0;
                    o_busy       <= 1'b0;
                    step_cnt     <= 6'd0;
                    
                    if (i_dac_sync) begin
                        // Форматирование 16-битного кадра DAC101S101:
                        // [15:12] = Настраиваемый режим работы (DAC_OP_MODE)
                        // [11:2]  = 10 бит данных ЦАП (r_dac_data)
                        // [1:0]   = 2'b00 (Младшие неиспользуемые биты / Don't Care)
                        shift_reg    <= {DAC_OP_MODE, r_dac_data, 2'b00};
                        o_dac_sync_n <= 1'b0;
                        o_busy       <= 1'b1;
                        state        <= STATE_TX;
                    end
                end

                STATE_TX: begin
                    step_cnt <= step_cnt + 1'b1;

                    if (step_cnt == 6'd32) begin
                        // Конец передачи (16 полных периодов SCLK, 32 такта dac_clk)
                        o_dac_sync_n <= 1'b1;
                        o_dac_sclk   <= 1'b1;
                        o_dac_sdin   <= 1'b0;
                        o_busy       <= 1'b0;
                        state        <= STATE_IDLE;
                    end else begin
                        // Деление dac_clk (50MHz) на 2 дает 25MHz SCLK (что меньше лимита микросхемы в 30MHz)
                        // SCLK в высоком уровне на четных тактах, в низком на нечетных
                        o_dac_sclk <= ~step_cnt[0];

                        // Сдвиг данных на спаде SCLK (подготовка к нарастающему фронту SCLK)
                        // Спаду SCLK соответствуют нечетные шаги автомата (1, 3, 5...).
                        if (step_cnt[0] == 1'b1) begin
                            shift_reg <= {shift_reg[14:0], 1'b0};
                        end

                        // Вывод текущего старшего бита (MSB) сдвигового регистра на линию MOSI
                        o_dac_sdin <= shift_reg[15];
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule