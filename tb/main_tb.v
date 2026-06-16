// =========================================================================
// Global AI Project Configuration
// Module: main_tb
// Description: Тестбенч для проверки главного модуля системы (main)
//              Генерирует все необходимые проектные частоты, подает 
//              команды настройки параметров, запускает синхронизацию и
//              эмулирует прием данных АЦП с последующим считыванием ascan.
// =========================================================================

`timescale 1ns / 1ps

module main_tb;

    // -------------------------------------------------------------------------
    // 1. Определение параметров тактовых частот (периоды в нс)
    // -------------------------------------------------------------------------
    // sys_clk: 80MHz  -> T = 12.5 ns  (полупериод 6.25 ns)
    // adc_clk: 65MHz  -> T = 15.385 ns (полупериод 7.6923 ns)
    // log_clk: 25MHz  -> T = 40.0 ns  (полупериод 20.0 ns)
    // dac_clk: 30MHz  -> T = 33.333 ns (полупериод 16.6667 ns)
    // hi_clk:  250MHz -> T = 4.0 ns   (полупериод 2.0 ns)
    
    localparam REAL_SYS_HALF_PERIOD = 6.25;
    localparam REAL_ADC_HALF_PERIOD = 7.6923;
    localparam REAL_LOG_HALF_PERIOD = 20.0;
    localparam REAL_DAC_HALF_PERIOD = 16.6667;
    localparam REAL_HI_HALF_PERIOD  = 2.0;

    // -------------------------------------------------------------------------
    // 2. Сигналы для подключения к тестируемому модулю (UUT)
    // -------------------------------------------------------------------------
    reg         sys_clk;
    reg         adc_clk;
    reg         log_clk;
    reg         dac_clk;
    reg         hi_clk;

    reg         rst_n;
    reg         i_sys_sync;

    // Интерфейс команд управления (в домене sys_clk)
    reg         i_cmd_val;
    reg  [31:0] i_cmd_addr;
    reg  [31:0] i_cmd_data;

    // Входные данные ADC (65MHz)
    reg  [11:0] i_adc_data;

    // Интерфейс выдачи упакованных данных ascan (80MHz, sys_clk)
    wire        o_ascan_ready;
    wire [15:0] o_ascan_size;
    wire [31:0] o_ascan_data;
    wire        o_ascan_vld;
    reg         i_ascan_rdy;

    // -------------------------------------------------------------------------
    // 3. Генераторы тактовых частот
    // -------------------------------------------------------------------------
    initial sys_clk = 1'b0;
    always #REAL_SYS_HALF_PERIOD sys_clk = ~sys_clk;

    initial adc_clk = 1'b0;
    always #REAL_ADC_HALF_PERIOD adc_clk = ~adc_clk;

    initial log_clk = 1'b0;
    always #REAL_LOG_HALF_PERIOD log_clk = ~log_clk;

    initial dac_clk = 1'b0;
    always #REAL_DAC_HALF_PERIOD dac_clk = ~dac_clk;

    initial hi_clk = 1'b0;
    always #REAL_HI_HALF_PERIOD hi_clk = ~hi_clk;

    // -------------------------------------------------------------------------
    // 4. Генерация входных данных АЦП (Counter pattern)
    // -------------------------------------------------------------------------
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            i_adc_data <= 12'h000;
        end else begin
            i_adc_data <= i_adc_data + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 5. Экземпляр тестируемого модуля (UUT)
    // -------------------------------------------------------------------------
    main uut (
        .sys_clk       (sys_clk),
        .adc_clk       (adc_clk),
        .log_clk       (log_clk),
        .dac_clk       (dac_clk),
        .hi_clk        (hi_clk),

        .rst_n         (rst_n),
        .i_sys_sync    (i_sys_sync),

        .i_cmd_val     (i_cmd_val),
        .i_cmd_addr    (i_cmd_addr),
        .i_cmd_data    (i_cmd_data),

        .i_adc_data    (i_adc_data),

        .o_ascan_ready (o_ascan_ready),
        .o_ascan_size  (o_ascan_size),
        .o_ascan_data  (o_ascan_data),
        .o_ascan_vld   (o_ascan_vld),
        .i_ascan_rdy   (i_ascan_rdy)
    );

    // -------------------------------------------------------------------------
    // 6. Сценарий тестирования (Stimulus)
    // -------------------------------------------------------------------------
    initial begin
        // Настройка сохранения дампов для симуляции
        $dumpfile("main_tb.vcd");
        $dumpvars(0, main_tb);

        // Инициализация сигналов
        rst_n       = 1'b0;
        i_sys_sync  = 1'b0;
        i_cmd_val   = 1'b0;
        i_cmd_addr  = 32'h0;
        i_cmd_data  = 32'h0;
        i_ascan_rdy = 1'b0;

        $display("[%0t] Симуляция начата. Активен асинхронный сброс.", $time);
        #150;
        
        // Снятие сброса
        @(posedge sys_clk);
        #1;
        rst_n = 1'b1;
        $display("[%0t] Асинхронный сброс снят.", $time);
        #200; // Ожидание инициализации и внутренней синхронизации модулей

        // --- Шаг 1: Конфигурация количества накапливаемых отсчетов для ascan ---
        // Согласно правилам проекта:
        // - Старший байт адреса команды: 2 (передать в adc_clk)
        // - Второй байт адреса команды: 1 (количество накапливаемых слов в adc_latch_param)
        // Настроим накопление на 32 слова.
        $display("[%0t] Шаг 1: Передача конфигурационной команды для домена ADC", $time);
        @(posedge sys_clk);
        #1;
        i_cmd_val  = 1'b1;
        i_cmd_addr = 32'h02010000; // Domain 2, Sub-addr 1
        i_cmd_data = 32'd32;       // Задаем 32 отсчета
        @(posedge sys_clk);
        #1;
        i_cmd_val  = 1'b0;
        i_cmd_addr = 32'h0;
        i_cmd_data = 32'h0;

        #200; // Ожидаем прохождения и защелкивания команды на частоте adc_clk

        // --- Шаг 2: Инициация цикла измерения (Сигнал i_sys_sync) ---
        $display("[%0t] Шаг 2: Генерация импульса синхронизации i_sys_sync", $time);
        @(posedge sys_clk);
        #1;
        i_sys_sync = 1'b1;
        @(posedge sys_clk);
        #1;
        i_sys_sync = 1'b0;

        // --- Шаг 3: Ожидание готовности накопленного буфера ---
        $display("[%0t] Шаг 3: Ожидание готовности данных ascan (o_ascan_ready)...", $time);
        fork
            begin
                // Таймаут в случае сбоя логики накопления
                #10000;
                $display("[%0t] Ошибка: Превышено время ожидания готовности данных (Timeout)!", $time);
                $finish;
            end
            begin
                wait(o_ascan_ready == 1'b1);
                $display("[%0t] Успех: Данные готовы! Количество слов в буфере: %0d", $time, o_ascan_size);
            end
        join_any
        disable fork;

        #100;

        // --- Шаг 4: Вычитывание упакованных данных из ascan ---
        $display("[%0t] Шаг 4: Чтение упакованных данных ascan", $time);
        @(posedge sys_clk);
        #1;
        i_ascan_rdy = 1'b1; // Объявляем готовность принимать данные

        // Читаем данные, пока активен флаг ready, либо в течение достаточного времени
        while (o_ascan_ready == 1'b1) begin
            @(posedge sys_clk);
            #1;
            if (o_ascan_vld) begin
                $display("[%0t] Успешно прочитано слово ascan: 0x%h", $time, o_ascan_data);
            end
        end

        // Снятие готовности приемника после окончания чтения
        @(posedge sys_clk);
        #1;
        i_ascan_rdy = 1'b0;
        
        #200;
        $display("[%0t] Тестирование успешно завершено.", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // 7. Мониторинг ключевых внутренних сигналов
    // -------------------------------------------------------------------------
    initial begin
        $monitor("[%0t] MON: i_sys_sync=%b, o_ascan_ready=%b, o_ascan_vld=%b, o_ascan_data=0x%h, i_ascan_rdy=%b",
                 $time, i_sys_sync, o_ascan_ready, o_ascan_vld, o_ascan_data, i_ascan_rdy);
    end

endmodule