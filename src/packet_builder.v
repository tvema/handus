// =============================================================================
// Module: packet_builder
// Description: Collects metadata (header), A-scan data, and log data, 
//              and formats them into a single packet on the sys_clk domain.
//              Packs all configuration parameters from sys_latch_param.v.
//              Transmission starts only when both A-scan and Log modules are ready.
// =============================================================================

module packet_builder (
    // Тактирование и сброс (домен sys_clk)
    input  wire        sys_clk,               // Частота 80MHz
    input  wire        sys_rst_n,             // Синхронизированный сброс (активный низкий)

    // Синхронизация запуска цикла
    input  wire        i_sys_sync,            // Импульс начала цикла от sync_cc

    // Системные параметры из sys_latch_param.v
    // 5.1. Параметры накопителя A-scana (Домен adc_clk / Префикс 0x02)
    input  wire [15:0] i_ascan_n_samples,
    input  wire [7:0]  i_ascan_accum,
    input  wire [3:0]  i_ascan_accum_type,
    input  wire [15:0] i_ascan_delay_time,

    // 5.2. Параметры логарифмического канала (Домен log_clk / Префикс 0x03)
    input  wire [15:0] i_log_n_samples,
    input  wire [7:0]  i_log_accum,
    input  wire [3:0]  i_log_accum_type,
    input  wire [3:0]  i_log_trans_meth,
    input  wire [15:0] i_log_skip_ticks,

    // 5.3. Параметры высоковольтного импульса (Домен hi_clk / Префикс 0x05)
    input  wire [15:0] i_pulse_charge_time,
    input  wire [15:0] i_pulse_transmit_time,
    input  wire [7:0]  i_pulse_width,

    // 5.4. Параметры генератора ВАРУ (Домен dac_clk / Префикс 0x04)
    input  wire [1:0]  i_vrc_type,
    input  wire [7:0]  i_vrc_dac_div,
    input  wire [15:0] i_vrc_start_delay,
    input  wire [10:0] i_vrc_init_gain,
    input  wire [31:0] i_vrc_rate_1,
    input  wire [15:0] i_vrc_duration_1,
    input  wire [31:0] i_vrc_rate_2,
    input  wire [15:0] i_vrc_duration_2,
    input  wire [9:0]  i_vrc_dac_min,
    input  wire [9:0]  i_vrc_dac_max,

    // Интерфейс данных от модуля ascan (частота sys_clk)
    input  wire        i_ascan_ready,         // Сигнал готовности данных от ascan (o_data_ready)
    input  wire [15:0] i_ascan_word_cnt,      // Количество 32-битных слов, готовых к отправке
    input  wire [31:0] i_ascan_data,          // Упакованные 32-битные данные (o_out_data)
    input  wire        i_ascan_vld,           // Валидность данных ascan (o_out_vld)
    output reg         o_ascan_rdy,           // Готовность принять данные (i_out_rdy для ascan)

    // Интерфейс данных от модуля log (частота sys_clk)
    input  wire        i_log_ready,           // Готовность лог-данных к чтению
    input  wire [15:0] i_log_word_cnt,        // Количество 32-битных слов, готовых к отправке
    input  wire [31:0] i_log_data,            // Данные логов
    input  wire        i_log_vld,             // Валидность данных логов
    output reg         o_log_rdy,             // Готовность принять данные от log

    // Выходной стриминговый интерфейс пакета (на частоте sys_clk во внешний приёмник)
    output reg  [31:0] o_out_data,            // Выходные данные пакета (Заголовок -> A-scan -> Log)
    output reg         o_out_vld,             // Валидность выходных данных
    input  wire        i_out_rdy,             // Готовность приемника пакета принимать данные
    
    // Статусные сигналы готовности пакета к передаче
    output reg         o_data_ready,          // Готовность пакета к передаче (высокий уровень на всё время отправки пакета)
    output reg  [15:0] o_out_size             // Общее количество 32-битных слов в готовом пакете
);

    // --- State Encoding ---
    localparam ST_IDLE          = 2'b00;
    localparam ST_HEADER        = 2'b01;
    localparam ST_ASCAN_PAYLOAD = 2'b10;
    localparam ST_LOG_PAYLOAD   = 2'b11;

    reg [1:0] state, next_state;

    // --- Internal Registers ---
    reg [3:0]  header_cnt;  // 14 words header requires 4-bit counter
    reg [15:0] ascan_cnt;
    reg [15:0] log_cnt;

    // Latched Payload Word Counts (Captured at launch trigger)
    reg [15:0] r_ascan_word_cnt;
    reg [15:0] r_log_word_cnt;

    // Latched Parameters (Stable copy for the entire packet assembly run)
    reg [15:0] r_ascan_n_samples;
    reg [7:0]  r_ascan_accum;
    reg [3:0]  r_ascan_accum_type;
    reg [15:0] r_ascan_delay_time;

    reg [15:0] r_log_n_samples;
    reg [7:0]  r_log_accum;
    reg [3:0]  r_log_accum_type;
    reg [3:0]  r_log_trans_meth;
    reg [15:0] r_log_skip_ticks;

    reg [15:0] r_pulse_charge_time;
    reg [15:0] r_pulse_transmit_time;
    reg [7:0]  r_pulse_width;

    reg [1:0]  r_vrc_type;
    reg [7:0]  r_vrc_dac_div;
    reg [15:0] r_vrc_start_delay;
    reg [10:0] r_vrc_init_gain;
    reg [31:0] r_vrc_rate_1;
    reg [15:0] r_vrc_duration_1;
    reg [31:0] r_vrc_rate_2;
    reg [15:0] r_vrc_duration_2;
    reg [9:0]  r_vrc_dac_min;
    reg [9:0]  r_vrc_dac_max;

    reg [31:0] packet_id_reg;

    // --- Packet ID Counter ---
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            packet_id_reg <= 32'd0;
        end else if (i_sys_sync) begin
            packet_id_reg <= packet_id_reg + 1'b1;
        end
    end

    // --- FSM Next State Logic ---
    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                // Start packet creation only when both modules have valid datasets ready
                if (i_ascan_ready && i_log_ready) begin
                    next_state = ST_HEADER;
                end
            end

            ST_HEADER: begin
                if (i_out_rdy && (header_cnt == 4'd13)) begin
                    if (r_ascan_word_cnt == 16'd0) begin
                        if (r_log_word_cnt == 16'd0)
                            next_state = ST_IDLE;
                        else
                            next_state = ST_LOG_PAYLOAD;
                    end else begin
                        next_state = ST_ASCAN_PAYLOAD;
                    end
                end
            end

            ST_ASCAN_PAYLOAD: begin
                if (i_ascan_vld && i_out_rdy && (ascan_cnt == r_ascan_word_cnt - 1'b1)) begin
                    if (r_log_word_cnt == 16'd0)
                        next_state = ST_IDLE;
                    else
                        next_state = ST_LOG_PAYLOAD;
                end
            end

            ST_LOG_PAYLOAD: begin
                if (i_log_vld && i_out_rdy && (log_cnt == r_log_word_cnt - 1'b1)) begin
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // --- FSM Sequential Logic ---
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state                 <= ST_IDLE;
            header_cnt            <= 4'd0;
            ascan_cnt             <= 16'd0;
            log_cnt               <= 16'd0;

            o_data_ready          <= 1'b0;
            o_out_size            <= 16'd0;

            r_ascan_word_cnt      <= 16'd0;
            r_log_word_cnt        <= 16'd0;

            r_ascan_n_samples     <= 16'd0;
            r_ascan_accum         <= 8'd0;
            r_ascan_accum_type    <= 4'd0;
            r_ascan_delay_time    <= 16'd0;

            r_log_n_samples       <= 16'd0;
            r_log_accum           <= 8'd0;
            r_log_accum_type      <= 4'd0;
            r_log_trans_meth      <= 4'd0;
            r_log_skip_ticks      <= 16'd0;

            r_pulse_charge_time   <= 16'd0;
            r_pulse_transmit_time <= 16'd0;
            r_pulse_width         <= 8'd0;

            r_vrc_type            <= 2'd0;
            r_vrc_dac_div         <= 8'd0;
            r_vrc_start_delay     <= 16'd0;
            r_vrc_init_gain       <= 11'd0;
            r_vrc_rate_1          <= 32'd0;
            r_vrc_duration_1      <= 16'd0;
            r_vrc_rate_2          <= 32'd0;
            r_vrc_duration_2      <= 16'd0;
            r_vrc_dac_min         <= 10'd0;
            r_vrc_dac_max         <= 10'd0;
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    header_cnt <= 4'd0;
                    ascan_cnt  <= 16'd0;
                    log_cnt    <= 16'd0;
                    
                    if (i_ascan_ready && i_log_ready) begin
                        // Set transaction active signals
                        o_data_ready          <= 1'b1;
                        o_out_size            <= 16'd14 + i_ascan_word_cnt + i_log_word_cnt;

                        // Latching actual sizes to read from each module buffer
                        r_ascan_word_cnt      <= i_ascan_word_cnt;
                        r_log_word_cnt        <= i_log_word_cnt;

                        // Latching all incoming configurations safely
                        r_ascan_n_samples     <= i_ascan_n_samples;
                        r_ascan_accum         <= i_ascan_accum;
                        r_ascan_accum_type    <= i_ascan_accum_type;
                        r_ascan_delay_time    <= i_ascan_delay_time;

                        r_log_n_samples       <= i_log_n_samples;
                        r_log_accum           <= i_log_accum;
                        r_log_accum_type      <= i_log_accum_type;
                        r_log_trans_meth      <= i_log_trans_meth;
                        r_log_skip_ticks      <= i_log_skip_ticks;

                        r_pulse_charge_time   <= i_pulse_charge_time;
                        r_pulse_transmit_time <= i_pulse_transmit_time;
                        r_pulse_width         <= i_pulse_width;

                        r_vrc_type            <= i_vrc_type;
                        r_vrc_dac_div         <= i_vrc_dac_div;
                        r_vrc_start_delay     <= i_vrc_start_delay;
                        r_vrc_init_gain       <= i_vrc_init_gain;
                        r_vrc_rate_1          <= i_vrc_rate_1;
                        r_vrc_duration_1      <= i_vrc_duration_1;
                        r_vrc_rate_2          <= i_vrc_rate_2;
                        r_vrc_duration_2      <= i_vrc_duration_2;
                        r_vrc_dac_min         <= i_vrc_dac_min;
                        r_vrc_dac_max         <= i_vrc_dac_max;
                    end else begin
                        o_data_ready  <= 1'b0;
                        o_out_size    <= 16'd0;
                    end
                end

                ST_HEADER: begin
                    if (i_out_rdy) begin
                        header_cnt <= header_cnt + 1'b1;
                        if (header_cnt == 4'd13) begin
                            header_cnt <= 4'd0;
                        end
                    end
                end

                ST_ASCAN_PAYLOAD: begin
                    if (i_ascan_vld && i_out_rdy) begin
                        ascan_cnt <= ascan_cnt + 1'b1;
                        if (ascan_cnt == r_ascan_word_cnt - 1'b1) begin
                            ascan_cnt <= 16'd0;
                        end
                    end
                end

                ST_LOG_PAYLOAD: begin
                    if (i_log_vld && i_out_rdy) begin
                        log_cnt <= log_cnt + 1'b1;
                        if (log_cnt == r_log_word_cnt - 1'b1) begin
                            log_cnt <= 16'd0;
                        end
                    end
                end
            endcase
        end
    end

    // --- Header Word Generator ---
    // 14 words mapping all parameters cleanly into 32-bit blocks
    reg [31:0] header_word;
    always @(*) begin
        case (header_cnt)
            4'd0:  header_word = 32'h5A5A5A5A;                                                    // Magic Number
            4'd1:  header_word = {16'd0, o_out_size};                                             // Total Packet Length (Header + Payloads)
            4'd2:  header_word = packet_id_reg;                                                   // Packet ID
            4'd3:  header_word = {r_ascan_n_samples, r_ascan_word_cnt};                           // Configured Samples | Actual Word Count
            4'd4:  header_word = {r_log_n_samples, r_log_word_cnt};                               // Configured Samples | Actual Word Count
            4'd5:  header_word = {r_ascan_delay_time, r_ascan_accum, r_ascan_accum_type, 4'd0};   // Ascan Delay & Accum parameters
            4'd6:  header_word = {r_log_skip_ticks, r_log_accum, r_log_accum_type, r_log_trans_meth}; // Log details
            4'd7:  header_word = {r_pulse_charge_time, r_pulse_transmit_time};                    // Pulse times
            4'd8:  header_word = {r_pulse_width, r_vrc_dac_div, r_vrc_type, 14'd0};               // Pulse width & VRC divider + type
            4'd9:  header_word = {r_vrc_start_delay, 5'd0, r_vrc_init_gain};                      // VRC Start delay & gain
            4'd10: header_word = {6'd0, r_vrc_dac_max, 6'd0, r_vrc_dac_min};                      // VRC Limits
            4'd11: header_word = r_vrc_rate_1;                                                    // VRC Rate 1
            4'd12: header_word = r_vrc_rate_2;                                                    // VRC Rate 2
            4'd13: header_word = {r_vrc_duration_1, r_vrc_duration_2};                            // VRC Durations 1 & 2
            default: header_word = 32'h00000000;
        endcase
    end

    // --- Output Routing Logic ---
    always @(*) begin
        // Defaults to avoid latches
        o_out_data  = 32'd0;
        o_out_vld   = 1'b0;
        o_ascan_rdy = 1'b0;
        o_log_rdy   = 1'b0;

        case (state)
            ST_IDLE: begin
                o_out_data  = 32'd0;
                o_out_vld   = 1'b0;
            end

            ST_HEADER: begin
                o_out_data  = header_word;
                o_out_vld   = 1'b1;
            end

            ST_ASCAN_PAYLOAD: begin
                o_out_data  = i_ascan_data;
                o_out_vld   = i_ascan_vld;
                o_ascan_rdy = i_out_rdy;
            end

            ST_LOG_PAYLOAD: begin
                o_out_data  = i_log_data;
                o_out_vld   = i_log_vld;
                o_log_rdy   = i_out_rdy;
            end
        endcase
    end

endmodule