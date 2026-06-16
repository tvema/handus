// =========================================================================
// Global AI Project Configuration
// Module: main
// Description: Главный модуль системы (Top-level)
// =========================================================================

module main (
    // Clock signals from PLL
    input wire sys_clk, // sys_clk: 80MHz
    input wire adc_clk, // adc_clk: 65MHz
    input wire log_clk, // log_clk: 25MHz
    input wire dac_clk, // dac_clk: 50MHz according to global config
    input wire hi_clk,  // hi_clk:  250MHz

    // Asynchronous reset (active low)
    input wire rst_n,

    // Внешний сигнал синхронизации в домене sys_clk
    input wire i_sys_sync,

    // Входной поток команд управления (в домене sys_clk)
    input wire        i_cmd_val,
    input wire [31:0] i_cmd_addr,
    input wire [31:0] i_cmd_data,

    // Входные данные ADC (65MHz)
    input wire [11:0] i_adc_data,

    // Входные данные Log ADC (25MHz)
    input wire [9:0]  i_log_adc_data,

    // Выходной стриминговый интерфейс сформированного пакета (80MHz, sys_clk)
    output wire [31:0] o_packet_data,  // Выходные данные пакета (Заголовок -> A-scan -> Log)
    output wire        o_packet_vld,   // Валидность выходных данных пакета
    input  wire        i_packet_rdy,   // Готовность внешнего приемника принимать пакет

    // Статусные сигналы готовности сформированного пакета
    output wire        o_packet_ready, // Готовность пакета к передаче (высокий уровень на всё время отправки пакета)
    output wire [15:0] o_packet_size,  // Общее количество 32-битных слов в готовом пакете

    // Выходы управления высоковольтным генератором (250MHz, hi_clk)
    output wire        o_pulse_turn_on, // Сигнал включения питания генератора
    output wire        o_pulse_strike,  // Сигнал запуска зондирующего импульса

    // Выходной интерфейс управления ЦАП ВАРУ (50MHz, dac_clk)
    output wire        o_dac_vld,       // Сигнал активности/нарастания ВРЧ
    output wire        o_dac_data_vld,  // Строб валидности данных для защелкивания в ЦАП (квитирование)
    output wire [9:0]  o_dac1,          // Выходной код для ЦАП 1 (10-бит)
    output wire [9:0]  o_dac2,          // Выходной код для ЦАП 2 (10-бит)
    input  wire        i_dac_rdy        // Готовность приемника ЦАП (dac_spi) к приему новых данных
);

    // -------------------------------------------------------------------------
    // Локальные сигналы синхронизации для каждого домена
    // -------------------------------------------------------------------------
    wire sys_sync;
    wire adc_sync;
    wire log_sync;
    wire dac_sync;
    wire hi_sync;

    // -------------------------------------------------------------------------
    // Локальные синхронизированные сбросы для каждого домена
    // -------------------------------------------------------------------------
    wire sys_rst_n;
    wire adc_rst_n;
    wire log_rst_n;
    wire dac_rst_n;
    wire hi_rst_n;

    // -------------------------------------------------------------------------
    // Внутренние шины параметров в домене sys_clk (для packet_builder)
    // -------------------------------------------------------------------------
    wire [15:0] sys_ascan_n_samples;
    wire [7:0]  sys_ascan_accum;
    wire [3:0]  sys_ascan_accum_type;
    wire [15:0] sys_ascan_delay_time;

    wire [15:0] sys_log_n_samples;
    wire [7:0]  sys_log_accum;
    wire [3:0]  sys_log_accum_type;
    wire [3:0]  sys_log_trans_meth;
    wire [15:0] sys_log_skip_ticks;

    wire [15:0] sys_pulse_charge_time;
    wire [15:0] sys_pulse_transmit_time;
    wire [7:0]  sys_pulse_width;

    wire [1:0]  sys_vrc_type;
    wire [7:0]  sys_vrc_dac_div;
    wire [15:0] sys_vrc_start_delay;
    wire [10:0] sys_vrc_init_gain;
    wire [31:0] sys_vrc_rate_1;
    wire [15:0] sys_vrc_duration_1;
    wire [31:0] sys_vrc_rate_2;
    wire [15:0] sys_vrc_duration_2;
    wire [9:0]  sys_vrc_dac_min;
    wire [9:0]  sys_vrc_dac_max;

    // -------------------------------------------------------------------------
    // Сигналы параметров (управляются param_hub в домене adc_clk)
    // -------------------------------------------------------------------------
    wire [15:0] adc_n_samples;  // Количество накапливаемых отсчетов для ascan
    wire [15:0] adc_skip_ticks; // Количество пропускаемых тактов перед стартом записи ascan
    wire [7:0]  adc_accum;      // Параметр "накопление" (коэффициент прореживания)
    wire [3:0]  adc_accum_type; // Параметр "тип накопления"

    // -------------------------------------------------------------------------
    // Сигналы параметров (управляются param_hub в домене log_clk)
    // -------------------------------------------------------------------------
    wire [15:0] log_n_samples;  // Количество накапливаемых отсчетов для log
    wire [7:0]  log_accum;      // Параметр накопления для log
    wire [3:0]  log_accum_type; // Тип накопления для log
    wire [3:0]  log_trans_meth; // Метод сжатия/передачи для log
    wire [15:0] log_skip_ticks; // Задержка старта log канала

    // -------------------------------------------------------------------------
    // Сигналы параметров (управляются param_hub в домене hi_clk)
    // -------------------------------------------------------------------------
    wire [15:0] hi_pulse_charge_time;
    wire [15:0] hi_pulse_transmit_time;
    wire [7:0]  hi_pulse_width;

    // -------------------------------------------------------------------------
    // Сигналы параметров (управляются param_hub в домене dac_clk)
    // -------------------------------------------------------------------------
    wire [1:0]  dac_vrc_type;
    wire [7:0]  dac_vrc_dac_div;
    wire [15:0] dac_vrc_start_delay;
    wire [10:0] dac_vrc_init_gain;
    wire [31:0] dac_vrc_rate_1;
    wire [15:0] dac_vrc_duration_1;
    wire [31:0] dac_vrc_rate_2;
    wire [15:0] dac_vrc_duration_2;
    wire [9:0]  dac_vrc_dac_min;
    wire [9:0]  dac_vrc_dac_max;

    // -------------------------------------------------------------------------
    // Локальные шины данных A-Scan (между u_ascan и u_packet_builder)
    // -------------------------------------------------------------------------
    wire        ascan_ready;
    wire [15:0] ascan_size;
    wire [31:0] ascan_data;
    wire        ascan_vld;
    wire        ascan_rdy;

    // -------------------------------------------------------------------------
    // Локальные шины данных Log-Scan (между u_log и u_packet_builder)
    // -------------------------------------------------------------------------
    wire        log_ready;
    wire [15:0] log_size;
    wire [31:0] log_data;
    wire        log_vld;
    wire        log_rdy;

    // -------------------------------------------------------------------------
    // Модуль междоменной синхронизации и генерации сбросов
    // -------------------------------------------------------------------------
    sync_cc u_sync_cc (
        // Входной тактовый сигнал домена sys_clk (80MHz) и глобальный сброс
        .clk         (sys_clk),
        .rst_n       (rst_n),

        // Входной сигнал синхронизации в домене sys_clk
        .i_sync      (i_sys_sync),

        // Тактовые частоты других доменов
        .i_adc_clk   (adc_clk),
        .i_log_clk   (log_clk),
        .i_dac_clk   (dac_clk),
        .i_hi_clk    (hi_clk),

        // Выходные синхронизированные импульсы для каждого домена
        .o_sys_sync  (sys_sync),
        .o_adc_sync  (adc_sync),
        .o_log_sync  (log_sync),
        .o_dac_sync  (dac_sync),
        .o_hi_sync   (hi_sync),

        // Выходные синхронизированные сбросы (активный низкий) для каждого домена
        .o_sys_rst_n (sys_rst_n),
        .o_adc_rst_n (adc_rst_n),
        .o_log_rst_n (log_rst_n),
        .o_dac_rst_n (dac_rst_n),
        .o_hi_rst_n  (hi_rst_n)
    );

    // -------------------------------------------------------------------------
    // Модуль распределения, CDC фильтрации и защелкивания параметров
    // -------------------------------------------------------------------------
    param_hub u_param_hub (
        // Входные тактовые частоты всех доменов
        .sys_clk                    (sys_clk),
        .adc_clk                    (adc_clk),
        .log_clk                    (log_clk),
        .dac_clk                    (dac_clk),
        .hi_clk                     (hi_clk),

        // Входные синхронизированные сбросы
        .sys_rst_n                  (sys_rst_n),
        .adc_rst_n                  (adc_rst_n),
        .log_rst_n                  (log_rst_n),
        .dac_rst_n                  (dac_rst_n),
        .hi_rst_n                   (hi_rst_n),

        // Входные синхронизированные импульсы запуска
        .i_sys_sync                 (sys_sync),
        .i_adc_sync                 (adc_sync),
        .i_log_sync                 (log_sync),
        .i_dac_sync                 (dac_sync),
        .i_hi_sync                  (hi_sync),

        // Входной командный поток (в домене sys_clk)
        .i_cmd_val                  (i_cmd_val),
        .i_cmd_addr                 (i_cmd_addr),
        .i_cmd_data                 (i_cmd_data),

        // Выходы: параметры системного домена (подключаются к packet_builder)
        .o_sys_ascan_n_samples     (sys_ascan_n_samples),
        .o_sys_ascan_accum         (sys_ascan_accum),
        .o_sys_ascan_accum_type    (sys_ascan_accum_type),
        .o_sys_ascan_delay_time    (sys_ascan_delay_time),
        .o_sys_log_n_samples       (sys_log_n_samples),
        .o_sys_log_accum           (sys_log_accum),
        .o_sys_log_accum_type      (sys_log_accum_type),
        .o_sys_log_trans_meth      (sys_log_trans_meth),
        .o_sys_log_skip_ticks      (sys_log_skip_ticks),
        .o_sys_pulse_charge_time   (sys_pulse_charge_time),
        .o_sys_pulse_transmit_time (sys_pulse_transmit_time),
        .o_sys_pulse_width         (sys_pulse_width),
        .o_sys_vrc_type            (sys_vrc_type),
        .o_sys_vrc_dac_div         (sys_vrc_dac_div),
        .o_sys_vrc_start_delay     (sys_vrc_start_delay),
        .o_sys_vrc_init_gain       (sys_vrc_init_gain),
        .o_sys_vrc_rate_1          (sys_vrc_rate_1),
        .o_sys_vrc_duration_1      (sys_vrc_duration_1),
        .o_sys_vrc_rate_2          (sys_vrc_rate_2),
        .o_sys_vrc_duration_2      (sys_vrc_duration_2),
        .o_sys_vrc_dac_min         (sys_vrc_dac_min),
        .o_sys_vrc_dac_max         (sys_vrc_dac_max),

        // Выходы: домен adc_clk (ascan_latch_param)
        .o_adc_ascan_n_samples     (adc_n_samples),
        .o_adc_ascan_accum         (adc_accum),
        .o_adc_ascan_accum_type    (adc_accum_type),
        .o_adc_ascan_skip_ticks    (adc_skip_ticks),

        // Выходы: домен log_clk
        .o_log_n_samples           (log_n_samples),
        .o_log_accum               (log_accum),
        .o_log_accum_type          (log_accum_type),
        .o_log_trans_meth          (log_trans_meth),
        .o_log_skip_ticks          (log_skip_ticks),

        // Выходы: домен dac_clk (подключаются к модулю vrc)
        .o_dac_vrc_type            (dac_vrc_type),
        .o_dac_vrc_dac_div         (dac_vrc_dac_div),
        .o_dac_vrc_start_delay     (dac_vrc_start_delay),
        .o_dac_vrc_init_gain       (dac_vrc_init_gain),
        .o_dac_vrc_rate_1          (dac_vrc_rate_1),
        .o_dac_vrc_duration_1      (dac_vrc_duration_1),
        .o_dac_vrc_rate_2          (dac_vrc_rate_2),
        .o_dac_vrc_duration_2      (dac_vrc_duration_2),
        .o_dac_vrc_dac_min         (dac_vrc_dac_min),
        .o_dac_vrc_dac_max         (dac_vrc_dac_max),

        // Выходы: домен hi_clk
        .o_hi_pulse_charge_time    (hi_pulse_charge_time),
        .o_hi_pulse_transmit_time  (hi_pulse_transmit_time),
        .o_hi_pulse_width          (hi_pulse_width)
    );

    // -------------------------------------------------------------------------
    // Модуль цифровой фильтрации КИХ (FIR Filter)
    // -------------------------------------------------------------------------
    wire [11:0] filtered_adc_data;
    wire        filtered_adc_vld; // Сигнал валидности с выхода фильтра (опционально)

    fir_filter u_fir_filter (
        .adc_clk    (adc_clk),
        .adc_rst_n  (adc_rst_n),
        .i_adc_sync (adc_sync),
        .i_adc_data (i_adc_data),
        .i_adc_vld  (1'b1), // Поток данных от АЦП поступает непрерывно на каждом такте
        .o_adc_data (filtered_adc_data),
        .o_adc_vld  (filtered_adc_vld)
    );

    // -------------------------------------------------------------------------
    // Модуль накопления и упаковки данных A-Scan (ascan.v)
    // -------------------------------------------------------------------------
    ascan #(
        .ADDR_WIDTH (11) // Глубина 2048 слов по 32 бита
    ) u_ascan (
        // Домен системной частоты (sys_clk: 80 МГц)
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),

        // Выходной интерфейс квитирования (на внутренние шины для packet_builder)
        .o_data_ready (ascan_ready),
        .o_out_size   (ascan_size),
        .o_out_data   (ascan_data),
        .o_out_vld    (ascan_vld),
        .i_out_rdy    (ascan_rdy),

        // Домен частоты АЦП (adc_clk: 65 МГц)
        .adc_clk      (adc_clk),
        .adc_rst_n    (adc_rst_n),
        .i_in_data    (filtered_adc_data), // Используем отфильтрованные данные
        .i_adc_sync   (adc_sync),
        .i_n_samples  (adc_n_samples),
        .i_skip_ticks (adc_skip_ticks),    // Параметр задержки старта
        .i_accum      (adc_accum),
        .i_accum_type (adc_accum_type)
    );

    // -------------------------------------------------------------------------
    // Модуль накопления, компрессии и упаковки данных Log-Scan (log.v)
    // -------------------------------------------------------------------------
    log #(
        .RAM_DEPTH (2048) // Глубина 2048 слов по 32 бита
    ) u_log (
        // Домены тактовых частот и сбросов
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),
        .log_clk      (log_clk),
        .log_rst_n    (log_rst_n),

        // Вход синхронизации в домене log_clk
        .i_log_sync   (log_sync),

        // Входные сырые данные от логарифмического АЦП
        .i_adc_data   (i_log_adc_data),

        // Конфигурационные параметры (подключены к param_hub)
        .i_n_samples  (log_n_samples),
        .i_accum      (log_accum),
        .i_accum_type (log_accum_type),
        .i_trans_meth (log_trans_meth),
        .i_skip_ticks (log_skip_ticks),

        // Выходной интерфейс выдачи данных (на внутренние шины для packet_builder)
        .o_out_data   (log_data),
        .o_out_vld    (log_vld),
        .i_out_rdy    (log_rdy),
        .o_data_ready (log_ready),
        .o_out_size   (log_size)
    );

    // -------------------------------------------------------------------------
    // Модуль управления высоковольтным импульсом (pulse.v)
    // -------------------------------------------------------------------------
    pulse u_pulse (
        .hi_rst_n         (hi_rst_n),
        .hi_clk           (hi_clk),
        .i_hi_sync        (hi_sync),
        .i_charge_time    (hi_pulse_charge_time),
        .i_transmit_time  (hi_pulse_transmit_time),
        .i_pulse_width    (hi_pulse_width),
        .o_turn_on        (o_pulse_turn_on),
        .o_strike         (o_pulse_strike)
    );

    // -------------------------------------------------------------------------
    // Модуль Временной Автоматической Регулировки Усиления (vrc.v)
    // -------------------------------------------------------------------------
    vrc #(
        .P (16) // Точность вычислений с фиксированной точкой (2^16)
    ) u_vrc (
        .dac_clk        (dac_clk),
        .dac_rst_n      (dac_rst_n),
        .i_dac_sync     (dac_sync),

        // Конфигурационные параметры (подключены к param_hub)
        .i_vrc_type     (dac_vrc_type),
        .i_dac_div      (dac_vrc_dac_div),
        .i_start_delay  (dac_vrc_start_delay),
        .i_init_gain    (dac_vrc_init_gain),
        .i_rate_1       (dac_vrc_rate_1),
        .i_duration_1   (dac_vrc_duration_1),
        .i_rate_2       (dac_vrc_rate_2),
        .i_duration_2   (dac_vrc_duration_2),
        .i_dac_min      (dac_vrc_dac_min),
        .i_dac_max      (dac_vrc_dac_max),

        // Интерфейсы передачи квитированием с ЦАП SPI
        .i_dac_rdy      (i_dac_rdy),
        .o_dac_vld      (o_dac_vld),
        .o_dac_data_vld (o_dac_data_vld),
        .o_dac1         (o_dac1),
        .o_dac2         (o_dac2)
    );

    // -------------------------------------------------------------------------
    // Модуль сборки и сериализации пакетов (packet_builder.v)
    // -------------------------------------------------------------------------
    packet_builder u_packet_builder (
        // Тактирование, сброс и сигнал синхронизации
        .sys_clk               (sys_clk),
        .sys_rst_n             (sys_rst_n),
        .i_sys_sync            (sys_sync),

        // Настройки A-scan
        .i_ascan_n_samples     (sys_ascan_n_samples),
        .i_ascan_accum         (sys_ascan_accum),
        .i_ascan_accum_type    (sys_ascan_accum_type),
        .i_ascan_delay_time    (sys_ascan_delay_time),

        // Настройки Log-scan
        .i_log_n_samples       (sys_log_n_samples),
        .i_log_accum           (sys_log_accum),
        .i_log_accum_type      (sys_log_accum_type),
        .i_log_trans_meth      (sys_log_trans_meth),
        .i_log_skip_ticks      (sys_log_skip_ticks),

        // Настройки Высоковольтного Генератора
        .i_pulse_charge_time   (sys_pulse_charge_time),
        .i_pulse_transmit_time (sys_pulse_transmit_time),
        .i_pulse_width         (sys_pulse_width),

        // Настройки ВАРУ (VRC)
        .i_vrc_type            (sys_vrc_type),
        .i_vrc_dac_div         (sys_vrc_dac_div),
        .i_vrc_start_delay     (sys_vrc_start_delay),
        .i_vrc_init_gain       (sys_vrc_init_gain),
        .i_vrc_rate_1          (sys_vrc_rate_1),
        .i_vrc_duration_1      (sys_vrc_duration_1),
        .i_vrc_rate_2          (sys_vrc_rate_2),
        .i_vrc_duration_2      (sys_vrc_duration_2),
        .i_vrc_dac_min         (sys_vrc_dac_min),
        .i_vrc_dac_max         (sys_vrc_dac_max),

        // Входной интерфейс A-Scan данных
        .i_ascan_ready         (ascan_ready),
        .i_ascan_word_cnt      (ascan_size),
        .i_ascan_data          (ascan_data),
        .i_ascan_vld           (ascan_vld),
        .o_ascan_rdy           (ascan_rdy),

        // Входной интерфейс Log-Scan данных
        .i_log_ready           (log_ready),
        .i_log_word_cnt        (log_size),
        .i_log_data            (log_data),
        .i_log_vld             (log_vld),
        .o_log_rdy             (log_rdy),

        // Внешний интерфейс выдачи готовых пакетов
        .o_out_data            (o_packet_data),
        .o_out_vld             (o_packet_vld),
        .i_out_rdy             (i_packet_rdy),

        // Статусные сигналы готовности пакета к передаче
        .o_data_ready          (o_packet_ready),
        .o_out_size            (o_packet_size)
    );

endmodule