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
    input wire dac_clk, // dac_clk: 30MHz
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

    // Интерфейс выдачи упакованных данных ascan (80MHz, sys_clk)
    output wire        o_ascan_ready, // Готовность буфера к чтению
    output wire [15:0] o_ascan_size,  // Количество слов в буфере на момент готовности
    output wire [31:0] o_ascan_data,  // Выход упакованных 32-битных слов
    output wire        o_ascan_vld,   // Валидность выходных данных
    input  wire        i_ascan_rdy    // Готовность приемника данных
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
    // Локальные шины команд для различных тактовых доменов
    // -------------------------------------------------------------------------
    wire        sys_cmd_val;
    wire [31:0] sys_cmd_addr;
    wire [31:0] sys_cmd_data;

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

    // -------------------------------------------------------------------------
    // Сигналы параметров (управляются модулем adc_latch_param)
    // -------------------------------------------------------------------------
    wire [15:0] adc_n_samples;  // Количество накапливаемых отсчетов для ascan
    wire [7:0]  adc_accum;      // Параметр "накопление" (коэффициент прореживания)
    wire [3:0]  adc_accum_type; // Параметр "тип накопления"

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
    // Модуль распределения и кроссдоменного переноса параметров
    // -------------------------------------------------------------------------
    param u_param (
        // Тактовые частоты всех доменов
        .sys_clk        (sys_clk),
        .adc_clk        (adc_clk),
        .log_clk        (log_clk),
        .dac_clk        (dac_clk),
        .hi_clk         (hi_clk),

        // Глобальный асинхронный сброс
        .rst_n          (rst_n),

        // Входной поток команд на sys_clk
        .i_cmd_val      (i_cmd_val),
        .i_cmd_addr     (i_cmd_addr),
        .i_cmd_data     (i_cmd_data),

        // Выходы для домена sys_clk (Domain 1)
        .o_sys_cmd_val  (sys_cmd_val),
        .o_sys_cmd_addr (sys_cmd_addr),
        .o_sys_cmd_data (sys_cmd_data),

        // Выходы для домена adc_clk (Domain 2)
        .o_adc_cmd_val  (adc_cmd_val),
        .o_adc_cmd_addr (adc_cmd_addr),
        .o_adc_cmd_data (adc_cmd_data),

        // Выходы для домена log_clk (Domain 3)
        .o_log_cmd_val  (log_cmd_val),
        .o_log_cmd_addr (log_cmd_addr),
        .o_log_cmd_data (log_cmd_data),

        // Выходы для домена dac_clk (Domain 4)
        .o_dac_cmd_val  (dac_cmd_val),
        .o_dac_cmd_addr (dac_cmd_addr),
        .o_dac_cmd_data (dac_cmd_data),

        // Выходы для домена hi_clk (Domain 5)
        .o_hi_cmd_val   (hi_cmd_val),
        .o_hi_cmd_addr  (hi_cmd_addr),
        .o_hi_cmd_data  (hi_cmd_data)
    );

    // -------------------------------------------------------------------------
    // Модуль декодирования и защелкивания параметров в домене частоты ADC
    // -------------------------------------------------------------------------
    adc_latch_param u_adc_latch_param (
        .adc_clk      (adc_clk),
        .adc_rst_n    (adc_rst_n),
        .i_adc_sync   (adc_sync),

        // Интерфейс команд от модуля param
        .i_cmd_val    (adc_cmd_val),
        .i_cmd_addr   (adc_cmd_addr),
        .i_cmd_data   (adc_cmd_data),

        // Защелкнутые параметры
        .o_n_samples  (adc_n_samples),
        .o_accum      (adc_accum),
        .o_accum_type (adc_accum_type)
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
    // Модуль накопления и упаковки данных A-Scan
    // -------------------------------------------------------------------------
    ascan #(
        .ADDR_WIDTH (11) // Глубина 2048 слов по 32 бита
    ) u_ascan (
        // Домен системной частоты (sys_clk: 80 МГц)
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),

        // Выходной интерфейс квитирования (домен sys_clk)
        .o_data_ready (o_ascan_ready),
        .o_out_size   (o_ascan_size),
        .o_out_data   (o_ascan_data),
        .o_out_vld    (o_ascan_vld),
        .i_out_rdy    (i_ascan_rdy),

        // Домен частоты АЦП (adc_clk: 65 МГц)
        .adc_clk      (adc_clk),
        .adc_rst_n    (adc_rst_n),
        .i_in_data    (filtered_adc_data), // Используем отфильтрованные данные
        .i_adc_sync   (adc_sync),
        .i_n_samples  (adc_n_samples),
        .i_accum      (adc_accum),
        .i_accum_type (adc_accum_type)
    );

endmodule