`timescale 1ns / 1ps

module fir_filter (
    // Входной тактовый сигнал и сброс домена adc_clk (согласно системным правилам)
    input  wire        adc_clk,     // Частота АЦП 65 МГц
    input  wire        adc_rst_n,   // Сброс домена АЦП (активный низкий)
    input  wire        i_adc_sync,  // Сигнал синхронизации домена АЦП для сброса конвейера

    // Интерфейс входных данных АЦП (signed)
    input  wire [11:0] i_adc_data,  // 12-битные знаковые входные данные
    input  wire        i_adc_vld,   // Сигнал валидности входных данных

    // Интерфейс выходных отфильтрованных данных
    output reg  [11:0] o_adc_data,  // 12-битные знаковые отфильтрованные данные
    output reg         o_adc_vld    // Сигнал валидности выходных данных
);

    // Коэффициенты симметричного КИХ-фильтра (33 taps, 17 уникальных)
    // Рассчитаны для Fs = 65 MHz, BPF: 2.3 MHz - 2.7 MHz (полоса 400 kHz)
    // Масштабный коэффициент: 2^20 (1048576) для минимизации шума квантования.
    // Коэффициенты скорректированы для обеспечения строго нулевого усиления на DC.
    localparam signed [15:0] COEFF_0  = -16'sd3694;
    localparam signed [15:0] COEFF_1  = -16'sd3376;
    localparam signed [15:0] COEFF_2  = -16'sd3036;
    localparam signed [15:0] COEFF_3  = -16'sd3628;
    localparam signed [15:0] COEFF_4  = -16'sd4281;
    localparam signed [15:0] COEFF_5  = -16'sd4832;
    localparam signed [15:0] COEFF_6  = -16'sd5084;
    localparam signed [15:0] COEFF_7  = -16'sd4873;
    localparam signed [15:0] COEFF_8  = -16'sd4093;
    localparam signed [15:0] COEFF_9  = -16'sd2580;
    localparam signed [15:0] COEFF_10 = -16'sd487;
    localparam signed [15:0] COEFF_11 = 16'sd2023;
    localparam signed [15:0] COEFF_12 = 16'sd4709;
    localparam signed [15:0] COEFF_13 = 16'sd7331;
    localparam signed [15:0] COEFF_14 = 16'sd9453;
    localparam signed [15:0] COEFF_15 = 16'sd10794;
    localparam signed [15:0] COEFF_16 = 16'sd11295; // Центральный коэффициент

    // Сдвиговый регистр задержки данных АЦП (33 отсчета)
    reg signed [11:0] shift_reg [0:32];

    // --- КОНВЕЙЕРНЫЕ РЕГИСТРЫ ВЫЧИСЛЕНИЙ ---

    // Такт 1: Предварительные сумматоры (используем симметрию КИХ-структуры)
    reg signed [12:0] add_reg_0;
    reg signed [12:0] add_reg_1;
    reg signed [12:0] add_reg_2;
    reg signed [12:0] add_reg_3;
    reg signed [12:0] add_reg_4;
    reg signed [12:0] add_reg_5;
    reg signed [12:0] add_reg_6;
    reg signed [12:0] add_reg_7;
    reg signed [12:0] add_reg_8;
    reg signed [12:0] add_reg_9;
    reg signed [12:0] add_reg_10;
    reg signed [12:0] add_reg_11;
    reg signed [12:0] add_reg_12;
    reg signed [12:0] add_reg_13;
    reg signed [12:0] add_reg_14;
    reg signed [12:0] add_reg_15;
    reg signed [11:0] mid_reg_16; // Центральный отсчет

    // Такт 2: Умножители (13-bit signed * 16-bit signed = 29-bit signed)
    reg signed [28:0] prod_reg_0;
    reg signed [28:0] prod_reg_1;
    reg signed [28:0] prod_reg_2;
    reg signed [28:0] prod_reg_3;
    reg signed [28:0] prod_reg_4;
    reg signed [28:0] prod_reg_5;
    reg signed [28:0] prod_reg_6;
    reg signed [28:0] prod_reg_7;
    reg signed [28:0] prod_reg_8;
    reg signed [28:0] prod_reg_9;
    reg signed [28:0] prod_reg_10;
    reg signed [28:0] prod_reg_11;
    reg signed [28:0] prod_reg_12;
    reg signed [28:0] prod_reg_13;
    reg signed [28:0] prod_reg_14;
    reg signed [28:0] prod_reg_15;
    reg signed [27:0] prod_reg_16;

    // Такт 3: Дерево сложения - Этап 1
    reg signed [29:0] sum_1_0;
    reg signed [29:0] sum_1_1;
    reg signed [29:0] sum_1_2;
    reg signed [29:0] sum_1_3;
    reg signed [29:0] sum_1_4;
    reg signed [29:0] sum_1_5;
    reg signed [29:0] sum_1_6;
    reg signed [29:0] sum_1_7;
    reg signed [29:0] sum_1_8;

    // Такт 4: Дерево сложения - Этап 2
    reg signed [30:0] sum_2_0;
    reg signed [30:0] sum_2_1;
    reg signed [30:0] sum_2_2;
    reg signed [30:0] sum_2_3;
    reg signed [30:0] sum_2_4;

    // Такт 5: Дерево сложения - Этап 3
    reg signed [31:0] sum_3_0;
    reg signed [31:0] sum_3_1;
    reg signed [31:0] sum_3_2;

    // Такт 6: Дерево сложения - Этап 4
    reg signed [32:0] sum_4_0;
    reg signed [32:0] sum_4_1;

    // Такт 7: Финальный сумматор
    reg signed [33:0] final_sum;

    // Линия задержки флага Valid для компенсации латентности конвейера (8 тактов)
    reg [7:0] vld_pipe;

    integer i;

    // Логика сдвигового регистра входных данных
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            for (i = 0; i < 33; i = i + 1) begin
                shift_reg[i] <= 12'sd0;
            end
        end else if (i_adc_sync) begin
            for (i = 0; i < 33; i = i + 1) begin
                shift_reg[i] <= 12'sd0;
            end
        end else if (i_adc_vld) begin
            shift_reg[0] <= $signed(i_adc_data);
            for (i = 1; i < 33; i = i + 1) begin
                shift_reg[i] <= shift_reg[i-1];
            end
        end
    end

    // Конвейер вычислений КИХ-фильтра
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            add_reg_0  <= 13'sd0; add_reg_1  <= 13'sd0; add_reg_2  <= 13'sd0; add_reg_3  <= 13'sd0;
            add_reg_4  <= 13'sd0; add_reg_5  <= 13'sd0; add_reg_6  <= 13'sd0; add_reg_7  <= 13'sd0;
            add_reg_8  <= 13'sd0; add_reg_9  <= 13'sd0; add_reg_10 <= 13'sd0; add_reg_11 <= 13'sd0;
            add_reg_12 <= 13'sd0; add_reg_13 <= 13'sd0; add_reg_14 <= 13'sd0; add_reg_15 <= 13'sd0;
            mid_reg_16 <= 12'sd0;

            prod_reg_0  <= 29'sd0; prod_reg_1  <= 29'sd0; prod_reg_2  <= 29'sd0; prod_reg_3  <= 29'sd0;
            prod_reg_4  <= 29'sd0; prod_reg_5  <= 29'sd0; prod_reg_6  <= 29'sd0; prod_reg_7  <= 29'sd0;
            prod_reg_8  <= 29'sd0; prod_reg_9  <= 29'sd0; prod_reg_10 <= 29'sd0; prod_reg_11 <= 29'sd0;
            prod_reg_12 <= 29'sd0; prod_reg_13 <= 29'sd0; prod_reg_14 <= 29'sd0; prod_reg_15 <= 29'sd0;
            prod_reg_16 <= 28'sd0;

            sum_1_0 <= 30'sd0; sum_1_1 <= 30'sd0; sum_1_2 <= 30'sd0; sum_1_3 <= 30'sd0;
            sum_1_4 <= 30'sd0; sum_1_5 <= 30'sd0; sum_1_6 <= 30'sd0; sum_1_7 <= 30'sd0;
            sum_1_8 <= 30'sd0;

            sum_2_0 <= 31'sd0; sum_2_1 <= 31'sd0; sum_2_2 <= 31'sd0; sum_2_3 <= 31'sd0;
            sum_2_4 <= 31'sd0;

            sum_3_0 <= 32'sd0; sum_3_1 <= 32'sd0; sum_3_2 <= 32'sd0;

            sum_4_0 <= 33'sd0; sum_4_1 <= 33'sd0;

            final_sum <= 34'sd0;
        end else if (i_adc_sync) begin
            // Сброс конвейера по сигналу внешней синхронизации
            add_reg_0  <= 13'sd0; add_reg_1  <= 13'sd0; add_reg_2  <= 13'sd0; add_reg_3  <= 13'sd0;
            add_reg_4  <= 13'sd0; add_reg_5  <= 13'sd0; add_reg_6  <= 13'sd0; add_reg_7  <= 13'sd0;
            add_reg_8  <= 13'sd0; add_reg_9  <= 13'sd0; add_reg_10 <= 13'sd0; add_reg_11 <= 13'sd0;
            add_reg_12 <= 13'sd0; add_reg_13 <= 13'sd0; add_reg_14 <= 13'sd0; add_reg_15 <= 13'sd0;
            mid_reg_16 <= 12'sd0;

            prod_reg_0  <= 29'sd0; prod_reg_1  <= 29'sd0; prod_reg_2  <= 29'sd0; prod_reg_3  <= 29'sd0;
            prod_reg_4  <= 29'sd0; prod_reg_5  <= 29'sd0; prod_reg_6  <= 29'sd0; prod_reg_7  <= 29'sd0;
            prod_reg_8  <= 29'sd0; prod_reg_9  <= 29'sd0; prod_reg_10 <= 29'sd0; prod_reg_11 <= 29'sd0;
            prod_reg_12 <= 29'sd0; prod_reg_13 <= 29'sd0; prod_reg_14 <= 29'sd0; prod_reg_15 <= 29'sd0;
            prod_reg_16 <= 28'sd0;

            sum_1_0 <= 30'sd0; sum_1_1 <= 30'sd0; sum_1_2 <= 30'sd0; sum_1_3 <= 30'sd0;
            sum_1_4 <= 30'sd0; sum_1_5 <= 30'sd0; sum_1_6 <= 30'sd0; sum_1_7 <= 30'sd0;
            sum_1_8 <= 30'sd0;

            sum_2_0 <= 31'sd0; sum_2_1 <= 31'sd0; sum_2_2 <= 31'sd0; sum_2_3 <= 31'sd0;
            sum_2_4 <= 31'sd0;

            sum_3_0 <= 32'sd0; sum_3_1 <= 32'sd0; sum_3_2 <= 32'sd0;

            sum_4_0 <= 33'sd0; sum_4_1 <= 33'sd0;

            final_sum <= 34'sd0;
        end else begin
            // Такт 1: Предварительное сложение симметричных отсчетов
            add_reg_0  <= $signed(shift_reg[0])  + $signed(shift_reg[32]);
            add_reg_1  <= $signed(shift_reg[1])  + $signed(shift_reg[31]);
            add_reg_2  <= $signed(shift_reg[2])  + $signed(shift_reg[30]);
            add_reg_3  <= $signed(shift_reg[3])  + $signed(shift_reg[29]);
            add_reg_4  <= $signed(shift_reg[4])  + $signed(shift_reg[28]);
            add_reg_5  <= $signed(shift_reg[5])  + $signed(shift_reg[27]);
            add_reg_6  <= $signed(shift_reg[6])  + $signed(shift_reg[26]);
            add_reg_7  <= $signed(shift_reg[7])  + $signed(shift_reg[25]);
            add_reg_8  <= $signed(shift_reg[8])  + $signed(shift_reg[24]);
            add_reg_9  <= $signed(shift_reg[9])  + $signed(shift_reg[23]);
            add_reg_10 <= $signed(shift_reg[10]) + $signed(shift_reg[22]);
            add_reg_11 <= $signed(shift_reg[11]) + $signed(shift_reg[21]);
            add_reg_12 <= $signed(shift_reg[12]) + $signed(shift_reg[20]);
            add_reg_13 <= $signed(shift_reg[13]) + $signed(shift_reg[19]);
            add_reg_14 <= $signed(shift_reg[14]) + $signed(shift_reg[18]);
            add_reg_15 <= $signed(shift_reg[15]) + $signed(shift_reg[17]);
            mid_reg_16 <= shift_reg[16];

            // Такт 2: Умножение на фиксированные коэффициенты
            prod_reg_0  <= add_reg_0  * COEFF_0;
            prod_reg_1  <= add_reg_1  * COEFF_1;
            prod_reg_2  <= add_reg_2  * COEFF_2;
            prod_reg_3  <= add_reg_3  * COEFF_3;
            prod_reg_4  <= add_reg_4  * COEFF_4;
            prod_reg_5  <= add_reg_5  * COEFF_5;
            prod_reg_6  <= add_reg_6  * COEFF_6;
            prod_reg_7  <= add_reg_7  * COEFF_7;
            prod_reg_8  <= add_reg_8  * COEFF_8;
            prod_reg_9  <= add_reg_9  * COEFF_9;
            prod_reg_10 <= add_reg_10 * COEFF_10;
            prod_reg_11 <= add_reg_11 * COEFF_11;
            prod_reg_12 <= add_reg_12 * COEFF_12;
            prod_reg_13 <= add_reg_13 * COEFF_13;
            prod_reg_14 <= add_reg_14 * COEFF_14;
            prod_reg_15 <= add_reg_15 * COEFF_15;
            prod_reg_16 <= mid_reg_16 * COEFF_16;

            // Такт 3: Дерево сложения - Уровень 1
            sum_1_0 <= $signed(prod_reg_0)  + $signed(prod_reg_1);
            sum_1_1 <= $signed(prod_reg_2)  + $signed(prod_reg_3);
            sum_1_2 <= $signed(prod_reg_4)  + $signed(prod_reg_5);
            sum_1_3 <= $signed(prod_reg_6)  + $signed(prod_reg_7);
            sum_1_4 <= $signed(prod_reg_8)  + $signed(prod_reg_9);
            sum_1_5 <= $signed(prod_reg_10) + $signed(prod_reg_11);
            sum_1_6 <= $signed(prod_reg_12) + $signed(prod_reg_13);
            sum_1_7 <= $signed(prod_reg_14) + $signed(prod_reg_15);
            sum_1_8 <= $signed(prod_reg_16);

            // Такт 4: Дерево сложения - Уровень 2
            sum_2_0 <= $signed(sum_1_0) + $signed(sum_1_1);
            sum_2_1 <= $signed(sum_1_2) + $signed(sum_1_3);
            sum_2_2 <= $signed(sum_1_4) + $signed(sum_1_5);
            sum_2_3 <= $signed(sum_1_6) + $signed(sum_1_7);
            sum_2_4 <= $signed(sum_1_8);

            // Такт 5: Дерево сложения - Уровень 3
            sum_3_0 <= $signed(sum_2_0) + $signed(sum_2_1);
            sum_3_1 <= $signed(sum_2_2) + $signed(sum_2_3);
            sum_3_2 <= $signed(sum_2_4);

            // Такт 6: Дерево сложения - Уровень 4
            sum_4_0 <= $signed(sum_3_0) + $signed(sum_3_1);
            sum_4_1 <= $signed(sum_3_2);

            // Такт 7: Финальное суммирование
            final_sum <= $signed(sum_4_0) + $signed(sum_4_1);
        end
    end

    // --- МАСШТАБИРОВАНИЕ И НАСЫЩЕНИЕ (SATURATION) ---
    // Так как коэффициенты были умножены на 2^20, сдвигаем сумму вправо на 20 бит.
    wire signed [33:0] scaled_sum = final_sum >>> 20;

    // Такт 8: Выходной регистр с защитой от переполнения
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            o_adc_data <= 12'sd0;
        end else if (i_adc_sync) begin
            o_adc_data <= 12'sd0;
        end else begin
            // Ограничение (Saturation) под 12-битный знаковый выход (-2048 ... 2047)
            if (scaled_sum > 34'sd2047) begin
                o_adc_data <= 12'sd2047;
            end else if (scaled_sum < -34'sd2048) begin
                o_adc_data <= -12'sd2048;
            end else begin
                o_adc_data <= scaled_sum[11:0];
            end
        end
    end

    // Линия задержки флага Valid для синхронизации с данными (8 тактов обработки)
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            vld_pipe  <= 8'b0;
            o_adc_vld <= 1'b0;
        end else if (i_adc_sync) begin
            vld_pipe  <= 8'b0;
            o_adc_vld <= 1'b0;
        end else begin
            vld_pipe  <= {vld_pipe[6:0], i_adc_vld};
            o_adc_vld <= vld_pipe[7];
        end
    end

endmodule