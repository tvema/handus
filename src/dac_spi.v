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

    // Потоковый интерфейс данных (в домене dac_clk)
    input  wire [9:0]  i_dac_data,      // 10-битное входное значение для ЦАП
    input  wire        i_dac_data_vld,  // Строб валидности данных (запускает трансляцию при o_dac_data_rdy)
    output reg         o_dac_data_rdy,  // Готовность к приему: '1' - свободен, '0' - идет передача

    // Аппаратный интерфейс ЦАП (SPI)
    output reg         o_dac_sclk,      // SPI Serial Clock (фиксированная частота 25 MHz = dac_clk / 2)
    output reg         o_dac_sdin,      // SPI Serial Data Input (SDIN/MOSI)
    output reg         o_dac_sync_n     // SPI Frame Sync (SYNC_N / CS_N)
);

    // Состояния конечного автомата (FSM)
    localparam STATE_IDLE = 1'b0;
    localparam STATE_TX   = 1'b1;

    reg        state;
    reg [4:0]  edge_cnt;        // Счетчик полупериодов SCLK (всего 32 перепада для передачи 16 бит)
    reg [15:0] shift_reg;       // Сдвиговый регистр кадра передачи

    // Конечный автомат передачи SPI
    always @(posedge dac_clk or negedge dac_rst_n) begin
        if (!dac_rst_n) begin
            state          <= STATE_IDLE;
            edge_cnt       <= 5'd0;
            shift_reg      <= 16'd0;
            o_dac_sclk     <= 1'b1;
            o_dac_sdin     <= 1'b0;
            o_dac_sync_n   <= 1'b1;
            o_dac_data_rdy <= 1'b1;
        end else begin
            case (state)
                STATE_IDLE: begin
                    o_dac_sync_n   <= 1'b1;
                    o_dac_sclk     <= 1'b1;
                    o_dac_sdin     <= 1'b0;
                    edge_cnt       <= 5'd0;
                    o_dac_data_rdy <= 1'b1; // Всегда готовы принять новые данные в простое
                    
                    // Запуск транзакции по приходу валидных данных
                    if (i_dac_data_vld) begin
                        // Форматируем 16-битный кадр ЦАП напрямую из входной шины:
                        // [15:12] = Настраиваемый режим работы (DAC_OP_MODE)
                        // [11:2]  = 10 бит данных ЦАП (i_dac_data)
                        // [1:0]   = 2'b00 (Младшие неиспользуемые биты / Don't Care)
                        shift_reg      <= {DAC_OP_MODE, i_dac_data, 2'b00};
                        o_dac_sync_n   <= 1'b0;
                        o_dac_data_rdy <= 1'b0; // Блокируем новые запросы
                        
                        // Сразу же выставляем старший бит (MSB) кадра на линию данных
                        o_dac_sdin     <= DAC_OP_MODE[3]; 
                        state          <= STATE_TX;
                    end
                end

                STATE_TX: begin
                    o_dac_data_rdy <= 1'b0; // Заняты передачей

                    if (edge_cnt == 5'd31) begin
                        // Конец передачи (все 16 бит переданы, SCLK вернулся в HIGH)
                        o_dac_sync_n   <= 1'b1;
                        o_dac_sclk     <= 1'b1;
                        o_dac_sdin     <= 1'b0;
                        o_dac_data_rdy <= 1'b1; // Разрешаем запись на следующем такте
                        state          <= STATE_IDLE;
                    end else begin
                        edge_cnt   <= edge_cnt + 1'b1;
                        o_dac_sclk <= ~o_dac_sclk; // Переключаем SCLK на каждом такте dac_clk (50MHz -> 25MHz)

                        // Сдвигаем данные на нарастающем фронте SCLK (когда текущий SCLK равен 0, а новый будет 1)
                        // DAC101S101 считывает данные на спаде SCLK, поэтому обновляем MOSI строго на фронте.
                        if (o_dac_sclk == 1'b0) begin
                            shift_reg  <= {shift_reg[14:0], 1'b0};
                            o_dac_sdin <= shift_reg[14]; // Выдаем следующий бит (MSB-1)
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule