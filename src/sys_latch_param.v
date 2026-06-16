// sys_latch_param.v
// Модуль для централизованного защёлкивания параметров всех доменов в тактовом домене sys_clk.
// Реализует двойную буферизацию (бабочку) параметров для синхронного обновления по сигналу i_sys_sync
// с автоматическим переключением активного буфера для чтения параметров.

`include "def_param.h"

module sys_latch_param (
    // Тактовый сигнал и сброс (домен sys_clk 80MHz)
    input wire sys_clk,
    input wire sys_rst_n,

    // Входной сигнал внешней синхронизации в домене sys_clk
    input wire i_sys_sync,

    // Входной интерфейс команд от модуля param
    input wire        i_cmd_vld,
    input wire [31:0] i_cmd_addr,
    input wire [31:0] i_cmd_data,

    // 5.1. Параметры накопителя A-scana (Домен adc_clk / Префикс 0x02)
    output wire [15:0] o_ascan_n_samples,
    output wire [7:0]  o_ascan_accum,
    output wire [3:0]  o_ascan_accum_type,
    output wire [15:0] o_ascan_delay_time,

    // 5.2. Параметры логарифмического канала (Домен log_clk / Префикс 0x03)
    output wire [15:0] o_log_n_samples,
    output wire [7:0]  o_log_accum,
    output wire [3:0]  o_log_accum_type,
    output wire [3:0]  o_log_trans_meth,
    output wire [15:0] o_log_skip_ticks,

    // 5.3. Параметры высоковольтного импульса (Домен hi_clk / Префикс 0x05)
    output wire [15:0] o_pulse_charge_time,
    output wire [15:0] o_pulse_transmit_time,
    output wire [7:0]  o_pulse_width,

    // 5.4. Параметры генератора ВАРУ (Домен dac_clk / Префикс 0x04)
    output wire [1:0]  o_vrc_type,
    output wire [7:0]  o_vrc_dac_div,
    output wire [15:0] o_vrc_start_delay,
    output wire [10:0] o_vrc_init_gain,
    output wire [31:0] o_vrc_rate_1,
    output wire [15:0] o_vrc_duration_1,
    output wire [31:0] o_vrc_rate_2,
    output wire [15:0] o_vrc_duration_2,
    output wire [9:0]  o_vrc_dac_min,
    output wire [9:0]  o_vrc_dac_max
);

    // =========================================================================
    // 1. Теневые регистры (Shadow Registers) для накопления команд param
    // =========================================================================
    reg [15:0] sh_ascan_n_samples;
    reg [7:0]  sh_ascan_accum;
    reg [3:0]  sh_ascan_accum_type;
    reg [15:0] sh_ascan_delay_time;

    reg [15:0] sh_log_n_samples;
    reg [7:0]  sh_log_accum;
    reg [3:0]  sh_log_accum_type;
    reg [3:0]  sh_log_trans_meth;
    reg [15:0] sh_log_skip_ticks;

    reg [15:0] sh_pulse_charge_time;
    reg [15:0] sh_pulse_transmit_time;
    reg [7:0]  sh_pulse_width;

    reg [1:0]  sh_vrc_type;
    reg [7:0]  sh_vrc_dac_div;
    reg [15:0] sh_vrc_start_delay;
    reg [10:0] sh_vrc_init_gain;
    reg [31:0] sh_vrc_rate_1;
    reg [15:0] sh_vrc_duration_1;
    reg [31:0] sh_vrc_rate_2;
    reg [15:0] sh_vrc_duration_2;
    reg [9:0]  sh_vrc_dac_min;
    reg [9:0]  sh_vrc_dac_max;

    // =========================================================================
    // 2. Двойные буферы хранения параметров (Buffer 0 и Buffer 1)
    // =========================================================================
    reg [15:0] b0_ascan_n_samples;
    reg [7:0]  b0_ascan_accum;
    reg [3:0]  b0_ascan_accum_type;
    reg [15:0] b0_ascan_delay_time;

    reg [15:0] b0_log_n_samples;
    reg [7:0]  b0_log_accum;
    reg [3:0]  b0_log_accum_type;
    reg [3:0]  b0_log_trans_meth;
    reg [15:0] b0_log_skip_ticks;

    reg [15:0] b0_pulse_charge_time;
    reg [15:0] b0_pulse_transmit_time;
    reg [7:0]  b0_pulse_width;

    reg [1:0]  b0_vrc_type;
    reg [7:0]  b0_vrc_dac_div;
    reg [15:0] b0_vrc_start_delay;
    reg [10:0] b0_vrc_init_gain;
    reg [31:0] b0_vrc_rate_1;
    reg [15:0] b0_vrc_duration_1;
    reg [31:0] b0_vrc_rate_2;
    reg [15:0] b0_vrc_duration_2;
    reg [9:0]  b0_vrc_dac_min;
    reg [9:0]  b0_vrc_dac_max;

    reg [15:0] b1_ascan_n_samples;
    reg [7:0]  b1_ascan_accum;
    reg [3:0]  b1_ascan_accum_type;
    reg [15:0] b1_ascan_delay_time;

    reg [15:0] b1_log_n_samples;
    reg [7:0]  b1_log_accum;
    reg [3:0]  b1_log_accum_type;
    reg [3:0]  b1_log_trans_meth;
    reg [15:0] b1_log_skip_ticks;

    reg [15:0] b1_pulse_charge_time;
    reg [15:0] b1_pulse_transmit_time;
    reg [7:0]  b1_pulse_width;

    reg [1:0]  b1_vrc_type;
    reg [7:0]  b1_vrc_dac_div;
    reg [15:0] b1_vrc_start_delay;
    reg [10:0] b1_vrc_init_gain;
    reg [31:0] b1_vrc_rate_1;
    reg [15:0] b1_vrc_duration_1;
    reg [31:0] b1_vrc_rate_2;
    reg [15:0] b1_vrc_duration_2;
    reg [9:0]  b1_vrc_dac_min;
    reg [9:0]  b1_vrc_dac_max;

    // Указатель записи параметров (показывает, какой буфер заполнится по следующему i_sys_sync)
    reg reg_wr_idx;

    // =========================================================================
    // 3. Логика записи параметров в Shadow и защёлкивание по i_sys_sync
    // =========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            reg_wr_idx <= 1'b0;

            // Инициализация теневых параметров значениями по умолчанию
            sh_ascan_n_samples    <= `INIT_ASCAN_N_SAMPLES;
            sh_ascan_accum        <= `INIT_ASCAN_ACCUM;
            sh_ascan_accum_type   <= `INIT_ASCAN_ACCUM_TYPE;
            sh_ascan_delay_time   <= `INIT_ASCAN_DELAY_TIME;

            sh_log_n_samples      <= `INIT_LOG_N_SAMPLES;
            sh_log_accum          <= `INIT_LOG_ACCUM;
            sh_log_accum_type     <= `INIT_LOG_ACCUM_TYPE;
            sh_log_trans_meth     <= `INIT_LOG_TRANS_METH;
            sh_log_skip_ticks     <= `INIT_LOG_SKIP_TICKS;

            sh_pulse_charge_time   <= `INIT_PULSE_CHARGE_TIME;
            sh_pulse_transmit_time <= `INIT_PULSE_TRANSMIT_TIME;
            sh_pulse_width         <= `INIT_PULSE_WIDTH;

            sh_vrc_type            <= `INIT_VRC_TYPE;
            sh_vrc_dac_div         <= `INIT_VRC_DAC_DIV;
            sh_vrc_start_delay     <= `INIT_VRC_START_DELAY;
            sh_vrc_init_gain       <= `INIT_VRC_INIT_GAIN;
            sh_vrc_rate_1          <= `INIT_VRC_RATE_1;
            sh_vrc_duration_1      <= `INIT_VRC_DURATION_1;
            sh_vrc_rate_2          <= `INIT_VRC_RATE_2;
            sh_vrc_duration_2      <= `INIT_VRC_DURATION_2;
            sh_vrc_dac_min         <= `INIT_VRC_DAC_MIN;
            sh_vrc_dac_max         <= `INIT_VRC_DAC_MAX;

            // Инициализация Буфера 0
            b0_ascan_n_samples    <= `INIT_ASCAN_N_SAMPLES;
            b0_ascan_accum        <= `INIT_ASCAN_ACCUM;
            b0_ascan_accum_type   <= `INIT_ASCAN_ACCUM_TYPE;
            b0_ascan_delay_time   <= `INIT_ASCAN_DELAY_TIME;

            b0_log_n_samples      <= `INIT_LOG_N_SAMPLES;
            b0_log_accum          <= `INIT_LOG_ACCUM;
            b0_log_accum_type     <= `INIT_LOG_ACCUM_TYPE;
            b0_log_trans_meth     <= `INIT_LOG_TRANS_METH;
            b0_log_skip_ticks     <= `INIT_LOG_SKIP_TICKS;

            b0_pulse_charge_time   <= `INIT_PULSE_CHARGE_TIME;
            b0_pulse_transmit_time <= `INIT_PULSE_TRANSMIT_TIME;
            b0_pulse_width         <= `INIT_PULSE_WIDTH;

            b0_vrc_type            <= `INIT_VRC_TYPE;
            b0_vrc_dac_div         <= `INIT_VRC_DAC_DIV;
            b0_vrc_start_delay     <= `INIT_VRC_START_DELAY;
            b0_vrc_init_gain       <= `INIT_VRC_INIT_GAIN;
            b0_vrc_rate_1          <= `INIT_VRC_RATE_1;
            b0_vrc_duration_1      <= `INIT_VRC_DURATION_1;
            b0_vrc_rate_2          <= `INIT_VRC_RATE_2;
            b0_vrc_duration_2      <= `INIT_VRC_DURATION_2;
            b0_vrc_dac_min         <= `INIT_VRC_DAC_MIN;
            b0_vrc_dac_max         <= `INIT_VRC_DAC_MAX;

            // Инициализация Буфера 1
            b1_ascan_n_samples    <= `INIT_ASCAN_N_SAMPLES;
            b1_ascan_accum        <= `INIT_ASCAN_ACCUM;
            b1_ascan_accum_type   <= `INIT_ASCAN_ACCUM_TYPE;
            b1_ascan_delay_time   <= `INIT_ASCAN_DELAY_TIME;

            b1_log_n_samples      <= `INIT_LOG_N_SAMPLES;
            b1_log_accum          <= `INIT_LOG_ACCUM;
            b1_log_accum_type     <= `INIT_LOG_ACCUM_TYPE;
            b1_log_trans_meth     <= `INIT_LOG_TRANS_METH;
            b1_log_skip_ticks     <= `INIT_LOG_SKIP_TICKS;

            b1_pulse_charge_time   <= `INIT_PULSE_CHARGE_TIME;
            b1_pulse_transmit_time <= `INIT_PULSE_TRANSMIT_TIME;
            b1_pulse_width         <= `INIT_PULSE_WIDTH;

            b1_vrc_type            <= `INIT_VRC_TYPE;
            b1_vrc_dac_div         <= `INIT_VRC_DAC_DIV;
            b1_vrc_start_delay     <= `INIT_VRC_START_DELAY;
            b1_vrc_init_gain       <= `INIT_VRC_INIT_GAIN;
            b1_vrc_rate_1          <= `INIT_VRC_RATE_1;
            b1_vrc_duration_1      <= `INIT_VRC_DURATION_1;
            b1_vrc_rate_2          <= `INIT_VRC_RATE_2;
            b1_vrc_duration_2      <= `INIT_VRC_DURATION_2;
            b1_vrc_dac_min         <= `INIT_VRC_DAC_MIN;
            b1_vrc_dac_max         <= `INIT_VRC_DAC_MAX;

        end else begin
            // 3.1 Защёлкивание параметров в Shadow-регистры из интерфейса param
            if (i_cmd_vld) begin
                case (i_cmd_addr[31:24])
                    // 5.1. Накопитель A-скана
                    8'h02: begin
                        case (i_cmd_addr[23:16])
                            8'h01: sh_ascan_n_samples    <= i_cmd_data[15:0];
                            8'h02: sh_ascan_accum        <= i_cmd_data[7:0];
                            8'h03: sh_ascan_accum_type   <= i_cmd_data[3:0];
                            8'h04: sh_ascan_delay_time   <= i_cmd_data[15:0];
                            default: ;
                        endcase
                    end

                    // 5.2. Логарифмический канал
                    8'h03: begin
                        case (i_cmd_addr[23:16])
                            8'h01: sh_log_n_samples      <= i_cmd_data[15:0];
                            8'h02: sh_log_accum          <= i_cmd_data[7:0];
                            8'h03: sh_log_accum_type     <= i_cmd_data[3:0];
                            8'h04: sh_log_trans_meth     <= i_cmd_data[3:0];
                            8'h05: sh_log_skip_ticks     <= i_cmd_data[15:0];
                            default: ;
                        endcase
                    end

                    // 5.4. Генератор ВАРУ
                    8'h04: begin
                        case (i_cmd_addr[23:16])
                            8'h01: begin
                                sh_vrc_type              <= i_cmd_data[1:0];
                                sh_vrc_dac_div           <= i_cmd_data[15:8];
                            end
                            8'h02: sh_vrc_start_delay    <= i_cmd_data[15:0];
                            8'h03: sh_vrc_init_gain      <= i_cmd_data[10:0];
                            8'h04: sh_vrc_rate_1         <= i_cmd_data[31:0];
                            8'h05: sh_vrc_duration_1     <= i_cmd_data[15:0];
                            8'h06: sh_vrc_rate_2         <= i_cmd_data[31:0];
                            8'h07: sh_vrc_duration_2     <= i_cmd_data[15:0];
                            8'h08: begin
                                sh_vrc_dac_min           <= i_cmd_data[9:0];
                                sh_vrc_dac_max           <= i_cmd_data[25:16];
                            end
                            default: ;
                        endcase
                    end

                    // 5.3. Высоковольтный импульс
                    8'h05: begin
                        case (i_cmd_addr[23:16])
                            8'h01: sh_pulse_charge_time   <= i_cmd_data[15:0];
                            8'h02: sh_pulse_transmit_time <= i_cmd_data[15:0];
                            8'h03: sh_pulse_width         <= i_cmd_data[7:0];
                            default: ;
                        endcase
                    end

                    default: ;
                endcase
            end

            // 3.2 Фиксация параметров по внешнему сигналу синхронизации
            if (i_sys_sync) begin
                if (reg_wr_idx == 1'b0) begin
                    b0_ascan_n_samples    <= sh_ascan_n_samples;
                    b0_ascan_accum        <= sh_ascan_accum;
                    b0_ascan_accum_type   <= sh_ascan_accum_type;
                    b0_ascan_delay_time   <= sh_ascan_delay_time;

                    b0_log_n_samples      <= sh_log_n_samples;
                    b0_log_accum          <= sh_log_accum;
                    b0_log_accum_type     <= sh_log_accum_type;
                    b0_log_trans_meth     <= sh_log_trans_meth;
                    b0_log_skip_ticks     <= sh_log_skip_ticks;

                    b0_pulse_charge_time   <= sh_pulse_charge_time;
                    b0_pulse_transmit_time <= sh_pulse_transmit_time;
                    b0_pulse_width         <= sh_pulse_width;

                    b0_vrc_type            <= sh_vrc_type;
                    b0_vrc_dac_div         <= sh_vrc_dac_div;
                    b0_vrc_start_delay     <= sh_vrc_start_delay;
                    b0_vrc_init_gain       <= sh_vrc_init_gain;
                    b0_vrc_rate_1          <= sh_vrc_rate_1;
                    b0_vrc_duration_1      <= sh_vrc_duration_1;
                    b0_vrc_rate_2          <= sh_vrc_rate_2;
                    b0_vrc_duration_2      <= sh_vrc_duration_2;
                    b0_vrc_dac_min         <= sh_vrc_dac_min;
                    b0_vrc_dac_max         <= sh_vrc_dac_max;
                end else begin
                    b1_ascan_n_samples    <= sh_ascan_n_samples;
                    b1_ascan_accum        <= sh_ascan_accum;
                    b1_ascan_accum_type   <= sh_ascan_accum_type;
                    b1_ascan_delay_time   <= sh_ascan_delay_time;

                    b1_log_n_samples      <= sh_log_n_samples;
                    b1_log_accum          <= sh_log_accum;
                    b1_log_accum_type     <= sh_log_accum_type;
                    b1_log_trans_meth     <= sh_log_trans_meth;
                    b1_log_skip_ticks     <= sh_log_skip_ticks;

                    b1_pulse_charge_time   <= sh_pulse_charge_time;
                    b1_pulse_transmit_time <= sh_pulse_transmit_time;
                    b1_pulse_width         <= sh_pulse_width;

                    b1_vrc_type            <= sh_vrc_type;
                    b1_vrc_dac_div         <= sh_vrc_dac_div;
                    b1_vrc_start_delay     <= sh_vrc_start_delay;
                    b1_vrc_init_gain       <= sh_vrc_init_gain;
                    b1_vrc_rate_1          <= sh_vrc_rate_1;
                    b1_vrc_duration_1      <= sh_vrc_duration_1;
                    b1_vrc_rate_2          <= sh_vrc_rate_2;
                    b1_vrc_duration_2      <= sh_vrc_duration_2;
                    b1_vrc_dac_min         <= sh_vrc_dac_min;
                    b1_vrc_dac_max         <= sh_vrc_dac_max;
                end
                // Переключаем индекс заполняемого буфера
                reg_wr_idx <= !reg_wr_idx;
            end
        end
    end

    // =========================================================================
    // 4. Коммутация параметров на выход (автовыбор буфера чтения)
    // =========================================================================
    // Так как буфер, на который указывает reg_wr_idx, будет перезаписан только 
    // при следующем импульсе i_sys_sync, в данный момент он хранит стабильные 
    // параметры предыдущего измерения (соответствующие считываемому буферу "бабочки")
    wire rd_buf_idx = reg_wr_idx;

    assign o_ascan_n_samples    = rd_buf_idx ? b1_ascan_n_samples    : b0_ascan_n_samples;
    assign o_ascan_accum        = rd_buf_idx ? b1_ascan_accum        : b0_ascan_accum;
    assign o_ascan_accum_type   = rd_buf_idx ? b1_ascan_accum_type   : b0_ascan_accum_type;
    assign o_ascan_delay_time   = rd_buf_idx ? b1_ascan_delay_time   : b0_ascan_delay_time;

    assign o_log_n_samples      = rd_buf_idx ? b1_log_n_samples      : b0_log_n_samples;
    assign o_log_accum          = rd_buf_idx ? b1_log_accum          : b0_log_accum;
    assign o_log_accum_type     = rd_buf_idx ? b1_log_accum_type     : b0_log_accum_type;
    assign o_log_trans_meth     = rd_buf_idx ? b1_log_trans_meth     : b0_log_trans_meth;
    assign o_log_skip_ticks     = rd_buf_idx ? b1_log_skip_ticks     : b0_log_skip_ticks;

    assign o_pulse_charge_time   = rd_buf_idx ? b1_pulse_charge_time   : b0_pulse_charge_time;
    assign o_pulse_transmit_time = rd_buf_idx ? b1_pulse_transmit_time : b0_pulse_transmit_time;
    assign o_pulse_width         = rd_buf_idx ? b1_pulse_width         : b0_pulse_width;

    assign o_vrc_type            = rd_buf_idx ? b1_vrc_type            : b0_vrc_type;
    assign o_vrc_dac_div         = rd_buf_idx ? b1_vrc_dac_div         : b0_vrc_dac_div;
    assign o_vrc_start_delay     = rd_buf_idx ? b1_vrc_start_delay     : b0_vrc_start_delay;
    assign o_vrc_init_gain       = rd_buf_idx ? b1_vrc_init_gain       : b0_vrc_init_gain;
    assign o_vrc_rate_1          = rd_buf_idx ? b1_vrc_rate_1          : b0_vrc_rate_1;
    assign o_vrc_duration_1      = rd_buf_idx ? b1_vrc_duration_1      : b0_vrc_duration_1;
    assign o_vrc_rate_2          = rd_buf_idx ? b1_vrc_rate_2          : b0_vrc_rate_2;
    assign o_vrc_duration_2      = rd_buf_idx ? b1_vrc_duration_2      : b0_vrc_duration_2;
    assign o_vrc_dac_min         = rd_buf_idx ? b1_vrc_dac_min         : b0_vrc_dac_min;
    assign o_vrc_dac_max         = rd_buf_idx ? b1_vrc_dac_max         : b0_vrc_dac_max;

endmodule