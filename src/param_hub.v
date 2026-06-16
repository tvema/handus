// src/param_hub.v

`default_nettype none

module param_hub (
    // Входные тактовые частоты (согласно правилу именования без "i_")
    input  wire        sys_clk,                  // 80 MHz
    input  wire        adc_clk,                  // 65 MHz
    input  wire        log_clk,                  // 25 MHz
    input  wire        dac_clk,                  // 50 MHz
    input  wire        hi_clk,                   // 250 MHz

    // Входные синхронизированные сбросы от sync_cc на уровне выше (без "i_")
    input  wire        sys_rst_n,
    input  wire        adc_rst_n,
    input  wire        log_rst_n,
    input  wire        dac_rst_n,
    input  wire        hi_rst_n,

    // Входные синхронизированные импульсы запуска от sync_cc на уровне выше (формат i_*_sync)
    input  wire        i_sys_sync,
    input  wire        i_adc_sync,
    input  wire        i_log_sync,
    input  wire        i_dac_sync,
    input  wire        i_hi_sync,

    // Входной командный поток (в домене sys_clk)
    input  wire        i_cmd_val,
    input  wire [31:0] i_cmd_addr,
    input  wire [31:0] i_cmd_data,

    // =========================================================================
    // ПАРАМЕТРЫ СИСТЕМНОГО ДОМЕНА (sys_clk, из sys_latch_param)
    // =========================================================================
    // Накопитель A-scana (Префикс 0x02)
    output wire [15:0] o_sys_ascan_n_samples,
    output wire [7:0]  o_sys_ascan_accum,
    output wire [3:0]  o_sys_ascan_accum_type,
    output wire [15:0] o_sys_ascan_delay_time,

    // Логарифмический канал (Префикс 0x03)
    output wire [15:0] o_sys_log_n_samples,
    output wire [7:0]  o_sys_log_accum,
    output wire [3:0]  o_sys_log_accum_type,
    output wire [3:0]  o_sys_log_trans_meth,
    output wire [15:0] o_sys_log_skip_ticks,

    // Высоковольтный импульс (Префикс 0x05)
    output wire [15:0] o_sys_pulse_charge_time,
    output wire [15:0] o_sys_pulse_transmit_time,
    output wire [7:0]  o_sys_pulse_width,

    // Генератор ВАРУ (Префикс 0x04)
    output wire [1:0]  o_sys_vrc_type,
    output wire [7:0]  o_sys_vrc_dac_div,
    output wire [15:0] o_sys_vrc_start_delay,
    output wire [10:0] o_sys_vrc_init_gain,
    output wire [31:0] o_sys_vrc_rate_1,
    output wire [15:0] o_sys_vrc_duration_1,
    output wire [31:0] o_sys_vrc_rate_2,
    output wire [15:0] o_sys_vrc_duration_2,
    output wire [9:0]  o_sys_vrc_dac_min,
    output wire [9:0]  o_sys_vrc_dac_max,

    // =========================================================================
    // ПАРАМЕТРЫ ЛОКАЛЬНЫХ ДОМЕНОВ (защёлкнутые по индивидуальным sync)
    // =========================================================================
    // Домен adc_clk (из ascan_latch_param)
    output wire [15:0] o_adc_ascan_n_samples,
    output wire [7:0]  o_adc_ascan_accum,
    output wire [3:0]  o_adc_ascan_accum_type,
    output wire [15:0] o_adc_ascan_skip_ticks,

    // Домен log_clk (из log_latch_param)
    output wire [15:0] o_log_n_samples,
    output wire [7:0]  o_log_accum,
    output wire [3:0]  o_log_accum_type,
    output wire [3:0]  o_log_trans_meth,
    output wire [15:0] o_log_skip_ticks,

    // Домен dac_clk (из vrc_param_latch)
    output wire [1:0]  o_dac_vrc_type,
    output wire [7:0]  o_dac_vrc_dac_div,
    output wire [15:0] o_dac_vrc_start_delay,
    output wire [10:0] o_dac_vrc_init_gain,
    output wire [31:0] o_dac_vrc_rate_1,
    output wire [15:0] o_dac_vrc_duration_1,
    output wire [31:0] o_dac_vrc_rate_2,
    output wire [15:0] o_dac_vrc_duration_2,
    output wire [9:0]  o_dac_vrc_dac_min,
    output wire [9:0]  o_dac_vrc_dac_max,

    // Домен hi_clk (из pulse_latch_param)
    output wire [15:0] o_hi_pulse_charge_time,
    output wire [15:0] o_hi_pulse_transmit_time,
    output wire [7:0]  o_hi_pulse_width
);

    //--------------------------------------------------------------------------
    // Внутренние соединительные командные шины после модуля param (CDC)
    //--------------------------------------------------------------------------
    wire        adc_cmd_val;
    wire [31:0] adc_cmd_addr;
    wire [31:0] adc_cmd_data;

    wire        log_cmd_val;
    wire [31:0] log_cmd_addr;
    wire [31:0] log_cmd_data;

    wire        dac_cmd_val;
    wire [31:0] dac_cmd_addr;
    wire [31:0] dac_cmd_data;

    wire        hi_cmd_val;
    wire [31:0] hi_cmd_addr;
    wire [31:0] hi_cmd_data;


    //--------------------------------------------------------------------------
    // 1. Модуль распределения и фильтрации команд (CDC FIFO)
    //--------------------------------------------------------------------------
    param u_param (
        .sys_clk        (sys_clk),
        .adc_clk        (adc_clk),
        .log_clk        (log_clk),
        .dac_clk        (dac_clk),
        .hi_clk         (hi_clk),
        .rst_n          (sys_rst_n), // Системный сброс от внешнего sync_cc

        // Входной поток команд
        .i_cmd_val      (i_cmd_val),
        .i_cmd_addr     (i_cmd_addr),
        .i_cmd_data     (i_cmd_data),

        // Выходы: Домен 1 (sys_clk) - не выводятся наружу, обрабатываются локально
        .o_sys_cmd_val  (),
        .o_sys_cmd_addr (),
        .o_sys_cmd_data (),

        // Выходы: Домен 2 (adc_clk)
        .o_adc_cmd_val  (adc_cmd_val),
        .o_adc_cmd_addr (adc_cmd_addr),
        .o_adc_cmd_data (adc_cmd_data),

        // Выходы: Домен 3 (log_clk)
        .o_log_cmd_val  (log_cmd_val),
        .o_log_cmd_addr (log_cmd_addr),
        .o_log_cmd_data (log_cmd_data),

        // Выходы: Домен 4 (dac_clk)
        .o_dac_cmd_val  (dac_cmd_val),
        .o_dac_cmd_addr (dac_cmd_addr),
        .o_dac_cmd_data (dac_cmd_data),

        // Выходы: Домен 5 (hi_clk)
        .o_hi_cmd_val   (hi_cmd_val),
        .o_hi_cmd_addr  (hi_cmd_addr),
        .o_hi_cmd_data  (hi_cmd_data)
    );


    //--------------------------------------------------------------------------
    // 2. Системный контроллер двойной буферизации параметров (sys_clk)
    //--------------------------------------------------------------------------
    sys_latch_param u_sys_latch_param (
        .sys_clk               (sys_clk),
        .sys_rst_n             (sys_rst_n),
        .i_sys_sync            (i_sys_sync),
        
        // Слушает оригинальный нефильтрованный поток команд для предварительного декодирования
        .i_cmd_vld             (i_cmd_val),
        .i_cmd_addr            (i_cmd_addr),
        .i_cmd_data            (i_cmd_data),

        // Выходы на порты верхнего уровня
        .o_ascan_n_samples     (o_sys_ascan_n_samples),
        .o_ascan_accum         (o_sys_ascan_accum),
        .o_ascan_accum_type    (o_sys_ascan_accum_type),
        .o_ascan_delay_time    (o_sys_ascan_delay_time),

        .o_log_n_samples       (o_sys_log_n_samples),
        .o_log_accum           (o_sys_log_accum),
        .o_log_accum_type      (o_sys_log_accum_type),
        .o_log_trans_meth      (o_sys_log_trans_meth),
        .o_log_skip_ticks      (o_sys_log_skip_ticks),

        .o_pulse_charge_time   (o_sys_pulse_charge_time),
        .o_pulse_transmit_time (o_sys_pulse_transmit_time),
        .o_pulse_width         (o_sys_pulse_width),

        .o_vrc_type            (o_sys_vrc_type),
        .o_vrc_dac_div         (o_sys_vrc_dac_div),
        .o_vrc_start_delay     (o_sys_vrc_start_delay),
        .o_vrc_init_gain       (o_sys_vrc_init_gain),
        .o_vrc_rate_1          (o_sys_vrc_rate_1),
        .o_vrc_duration_1      (o_sys_vrc_duration_1),
        .o_vrc_rate_2          (o_sys_vrc_rate_2),
        .o_vrc_duration_2      (o_sys_vrc_duration_2),
        .o_vrc_dac_min         (o_sys_vrc_dac_min),
        .o_vrc_dac_max         (o_sys_vrc_dac_max)
    );


    //--------------------------------------------------------------------------
    // 3. Локальный накопитель параметров А-скана (adc_clk)
    //--------------------------------------------------------------------------
    ascan_latch_param u_ascan_latch_param (
        .adc_clk      (adc_clk),
        .adc_rst_n    (adc_rst_n),
        .i_adc_sync   (i_adc_sync),

        .i_cmd_val    (adc_cmd_val),
        .i_cmd_addr   (adc_cmd_addr),
        .i_cmd_data   (adc_cmd_data),

        .o_n_samples  (o_adc_ascan_n_samples),
        .o_accum      (o_adc_ascan_accum),
        .o_accum_type (o_adc_ascan_accum_type),
        .o_skip_ticks (o_adc_ascan_skip_ticks)
    );


    //--------------------------------------------------------------------------
    // 4. Локальный накопитель параметров лог-канала (log_clk)
    //--------------------------------------------------------------------------
    log_latch_param u_log_latch_param (
        .log_clk      (log_clk),
        .log_rst_n    (log_rst_n),
        .i_log_sync   (i_log_sync),

        .i_cmd_val    (log_cmd_val),
        .i_cmd_addr   (log_cmd_addr),
        .i_cmd_data   (log_cmd_data),

        .o_n_samples  (o_log_n_samples),
        .o_accum      (o_log_accum),
        .o_accum_type (o_log_accum_type),
        .o_trans_meth (o_log_trans_meth),
        .o_skip_ticks (o_log_skip_ticks)
    );


    //--------------------------------------------------------------------------
    // 5. Локальный накопитель параметров ВАРУ (dac_clk)
    //--------------------------------------------------------------------------
    vrc_param_latch u_vrc_param_latch (
        .dac_clk       (dac_clk),
        .dac_rst_n     (dac_rst_n),
        .i_dac_sync    (i_dac_sync),

        .i_cmd_val     (dac_cmd_val),
        .i_cmd_addr    (dac_cmd_addr),
        .i_cmd_data    (dac_cmd_data),

        .o_vrc_type    (o_dac_vrc_type),
        .o_dac_div     (o_dac_vrc_dac_div),
        .o_start_delay (o_dac_vrc_start_delay),
        .o_init_gain   (o_dac_vrc_init_gain),
        .o_rate_1      (o_dac_vrc_rate_1),
        .o_duration_1  (o_dac_vrc_duration_1),
        .o_rate_2      (o_dac_vrc_rate_2),
        .o_duration_2  (o_dac_vrc_duration_2),
        .o_dac_min     (o_dac_vrc_dac_min),
        .o_dac_max     (o_dac_vrc_dac_max)
    );


    //--------------------------------------------------------------------------
    // 6. Локальный накопитель параметров высоковольтного импульса (hi_clk)
    //--------------------------------------------------------------------------
    pulse_latch_param u_pulse_latch_param (
        .hi_clk          (hi_clk),
        .hi_rst_n        (hi_rst_n),
        .i_hi_sync       (i_hi_sync),

        .i_cmd_val       (hi_cmd_val),
        .i_cmd_addr      (hi_cmd_addr),
        .i_cmd_data      (hi_cmd_data),

        .o_charge_time   (o_hi_pulse_charge_time),
        .o_transmit_time (o_hi_pulse_transmit_time),
        .o_pulse_width   (o_hi_pulse_width)
    );

endmodule

`default_nettype wire