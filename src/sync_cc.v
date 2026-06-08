// =========================================================================
// Global AI Project Configuration
// Module: sync_cc
// Description: Модуль междоменной синхронизации сигнала i_sync
//              и генерации синхронных сбросов для всех доменов проекта.
// =========================================================================

module sync_cc (
    // Входной тактовый сигнал домена sys_clk (80MHz) и глобальный сброс
    input  wire clk,         // sys_clk (80MHz) согласно правилу наименования
    input  wire rst_n,       // Асинхронный сброс (активный низкий)

    // Входной сигнал синхронизации в домене sys_clk
    input  wire i_sync,      // Сигнал внешней синхронизации

    // Тактовые частоты других доменов
    input  wire i_adc_clk,   // adc_clk: 65MHz
    input  wire i_log_clk,   // log_clk: 25MHz
    input  wire i_dac_clk,   // dac_clk: 30MHz
    input  wire i_hi_clk,    // hi_clk:  250MHz

    // Выходные синхронизированные импульсы для каждого домена
    output wire o_sys_sync,  // Синхронизирован в sys_clk (80MHz)
    output wire o_adc_sync,  // Синхронизирован в adc_clk (65MHz)
    output wire o_log_sync,  // Синхронизирован в log_clk (25MHz)
    output wire o_dac_sync,  // ... в dac_clk (30MHz)
    output wire o_hi_sync,   // ... в hi_clk (250MHz)

    // Выходные синхронизированные сбросы (активный низкий) для каждого домена
    output wire o_sys_rst_n, // Сброс для домена sys_clk (80MHz)
    output wire o_adc_rst_n, // Сброс для домена adc_clk (65MHz)
    output wire o_log_rst_n, // Сброс для домена log_clk (25MHz)
    output wire o_dac_rst_n, // Сброс для домена dac_clk (30MHz)
    output wire o_hi_rst_n   // Сброс для домена hi_clk  (250MHz)
);

    // -------------------------------------------------------------------------
    // 1. Выход для собственного домена sys_clk (простая регистризация)
    // -------------------------------------------------------------------------
    reg r_sync_sys;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_sync_sys <= 1'b0;
        else
            r_sync_sys <= i_sync;
    end
    assign o_sys_sync = r_sync_sys;

    // -------------------------------------------------------------------------
    // 2. CDC (Clock Domain Crossing) для импульса i_sync
    // Используется Toggle-CDC, так как целевые частоты могут быть ниже исходной.
    // -------------------------------------------------------------------------

    // Перекрестная синхронизация в домен ADC (65 MHz)
    sync_pulse_cdc u_sync_adc (
        .i_clk_in  (clk),
        .rst_n     (rst_n),
        .i_pulse   (i_sync),
        .i_clk_out (i_adc_clk),
        .o_pulse   (o_adc_sync)
    );

    // Перекрестная синхронизация в домен LOG (25 MHz)
    sync_pulse_cdc u_sync_log (
        .i_clk_in  (clk),
        .rst_n     (rst_n),
        .i_pulse   (i_sync),
        .i_clk_out (i_log_clk),
        .o_pulse   (o_log_sync)
    );

    // Перекрестная синхронизация в домен DAC (30 MHz)
    sync_pulse_cdc u_sync_dac (
        .i_clk_in  (clk),
        .rst_n     (rst_n),
        .i_pulse   (i_sync),
        .i_clk_out (i_dac_clk),
        .o_pulse   (o_dac_sync)
    );

    // Перекрестная синхронизация в быстрый домен HI (250 MHz)
    sync_pulse_cdc u_sync_hi (
        .i_clk_in  (clk),
        .rst_n     (rst_n),
        .i_pulse   (i_sync),
        .i_clk_out (i_hi_clk),
        .o_pulse   (o_hi_sync)
    );

    // -------------------------------------------------------------------------
    // 3. Генерация индивидуальных синхронных сбросов для каждого домена
    // -------------------------------------------------------------------------

    // Сброс для sys_clk (80MHz)
    sync_reset_cdc u_rst_sys (
        .clk     (clk),
        .rst_n   (rst_n),
        .o_rst_n (o_sys_rst_n)
    );

    // Сброс для adc_clk (65MHz)
    sync_reset_cdc u_rst_adc (
        .clk     (i_adc_clk),
        .rst_n   (rst_n),
        .o_rst_n (o_adc_rst_n)
    );

    // Сброс для log_clk (25MHz)
    sync_reset_cdc u_rst_log (
        .clk     (i_log_clk),
        .rst_n   (rst_n),
        .o_rst_n (o_log_rst_n)
    );

    // Сброс для dac_clk (30MHz)
    sync_reset_cdc u_rst_dac (
        .clk     (i_dac_clk),
        .rst_n   (rst_n),
        .o_rst_n (o_dac_rst_n)
    );

    // Сброс для hi_clk (250MHz)
    sync_reset_cdc u_rst_hi (
        .clk     (i_hi_clk),
        .rst_n   (rst_n),
        .o_rst_n (o_hi_rst_n)
    );

endmodule


// =========================================================================
// Вспомогательный модуль для безопасного переноса одиночного импульса (CDC)
// =========================================================================
module sync_pulse_cdc (
    input  wire i_clk_in,
    input  wire rst_n,
    input  wire i_pulse,
    input  wire i_clk_out,
    output wire o_pulse
);

    reg r_src_toggle;

    // 1. Переводим импульс в изменение уровня (Toggle) в исходном домене
    always @(posedge i_clk_in or negedge rst_n) begin
        if (!rst_n)
            r_src_toggle <= 1'b0;
        else if (i_pulse)
            r_src_toggle <= ~r_src_toggle;
    end

    // 2. Синхронизируем уровень в целевом домене с помощью 3-ступенчатого триггера
    // (3 ступени обеспечивают повышенную надежность на высоких частотах до 250MHz)
    reg [2:0] r_dst_sync;
    always @(posedge i_clk_out or negedge rst_n) begin
        if (!rst_n)
            r_dst_sync <= 3'b0;
        else
            r_dst_sync <= {r_dst_sync[1:0], r_src_toggle};
    end

    // 3. Восстанавливаем импульс в целевом домене через детектор изменения уровня (XOR)
    assign o_pulse = r_dst_sync[2] ^ r_dst_sync[1];

endmodule


// =========================================================================
// Вспомогательный модуль синхронизации сброса (Reset Bridge)
// Асинхронный спад, синхронный подъем
// =========================================================================
module sync_reset_cdc (
    input  wire clk,         // Локальный тактовый сигнал домена
    input  wire rst_n,       // Глобальный асинхронный сброс (вход)
    output wire o_rst_n      // Синхронизированный сброс домена (выход)
);

    // 3-ступенчатая синхронизация для надежной работы на частотах до 250 MHz
    reg [2:0] r_rst_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_rst_sync <= 3'b000;
        end else begin
            // Задвигаем "единицу" по переднему фронту тактового сигнала
            r_rst_sync <= {r_rst_sync[1:0], 1'b1};
        end
    end

    // Сигнал сброса снимается только после того, как "единица" пройдет всю цепочку
    assign o_rst_n = r_rst_sync[2];

endmodule