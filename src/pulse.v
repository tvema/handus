// New file
module pulse(
    input               hi_rst_n,
    input               hi_clk,

    input               i_hi_sync,

    input   [15:0]      i_charge_time,
    input   [15:0]      i_transmit_time,
    input   [7:0]       i_pulse_width,

    output              o_turn_on,
    output              o_strike
);

    // Определение состояний автомата
    localparam STATE_NONE      = 3'd0;
    localparam STATE_CHARGE    = 3'd1;
    localparam STATE_TRANSMIT  = 3'd2;
    localparam STATE_STRIKE    = 3'd3;
    localparam STATE_POWER_OFF = 3'd4;

    reg [2:0]  state;
    reg [15:0] cnt;

    reg r_turn_on;
    reg r_strike;

    // Назначение зарегистрированных выходов
    assign o_turn_on = r_turn_on;
    assign o_strike  = r_strike;

    // Работа автомата состояний и формирование сигналов управления
    always @(posedge hi_clk or negedge hi_rst_n) begin
        if (!hi_rst_n) begin
            state     <= STATE_NONE;
            cnt       <= 16'd0;
            r_turn_on <= 1'b0;
            r_strike  <= 1'b0;
        end else begin
            case (state)
                // Ожидание сигнала внешней синхронизации
                STATE_NONE: begin
                    r_turn_on <= 1'b0;
                    r_strike  <= 1'b0;
                    
                    if (i_hi_sync) begin
                        state     <= STATE_CHARGE;
                        cnt       <= 16'd1;
                        r_turn_on <= 1'b1;
                        r_strike  <= 1'b1;
                    end else begin
                        cnt <= 16'd0;
                    end
                end

                // Накопление энергии (Charge Power)
                STATE_CHARGE: begin
                    if (cnt >= i_charge_time) begin
                        state     <= STATE_TRANSMIT;
                        cnt       <= 16'd1;
                        r_turn_on <= 1'b1;
                        r_strike  <= 1'b0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // Передача мощности (Transmit Power)
                STATE_TRANSMIT: begin
                    if (cnt >= i_transmit_time) begin
                        state     <= STATE_STRIKE;
                        cnt       <= 16'd1;
                        r_turn_on <= 1'b1;
                        r_strike  <= 1'b0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // Зондирующий импульс (Strike)
                STATE_STRIKE: begin
                    if (cnt >= i_pulse_width) begin
                        state     <= STATE_POWER_OFF;
                        cnt       <= 16'd1;
                        r_turn_on <= 1'b0;
                        r_strike  <= 1'b0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // Выключение питания и технологическая пауза (минимум 200 тактов)
                STATE_POWER_OFF: begin
                    if (cnt >= 16'd200) begin
                        state     <= STATE_NONE;
                        cnt       <= 16'd0;
                        r_turn_on <= 1'b0;
                        r_strike  <= 1'b0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: begin
                    state     <= STATE_NONE;
                    cnt       <= 16'd0;
                    r_turn_on <= 1'b0;
                    r_strike  <= 1'b0;
                end
            endcase
        end
    end

endmodule