`timescale 1ns / 1ps

module dac_spi_tb;

    // Параметры для теста
    localparam [3:0] TB_DAC_OP_MODE = 4'b0000; // Режим работы Normal Operation

    // Сигналы генератора тактовой частоты и сброса
    reg        dac_clk;
    reg        dac_rst_n;

    // Входные сигналы для тестируемого модуля (UUT)
    reg [9:0]  i_dac_data;
    reg        i_dac_data_vld;

    // Выходные сигналы из тестируемого модуля (UUT)
    wire       o_dac_data_rdy;
    wire       o_dac_sclk;
    wire       o_dac_sdin;
    wire       o_dac_sync_n;

    // Инстанцирование тестируемого модуля (UUT)
    dac_spi #(
        .DAC_OP_MODE(TB_DAC_OP_MODE)
    ) uut (
        .dac_clk       (dac_clk),
        .dac_rst_n     (dac_rst_n),
        .i_dac_data    (i_dac_data),
        .i_dac_data_vld(i_dac_data_vld),
        .o_dac_data_rdy(o_dac_data_rdy),
        .o_dac_sclk    (o_dac_sclk),
        .o_dac_sdin    (o_dac_sdin),
        .o_dac_sync_n  (o_dac_sync_n)
    );

    // Генерация тактового сигнала dac_clk (50MHz -> период 20нс)
    always begin
        dac_clk = 1'b0;
        #10;
        dac_clk = 1'b1;
        #10;
    end

    // Монитор принимаемых SPI данных (эмуляция приемника DAC101S101)
    reg [15:0] captured_word;
    integer    bit_idx;

    initial begin
        captured_word = 16'd0;
        bit_idx       = 0;
    end

    // Захват последовательных данных на линии SDIN по спаду SCLK
    always @(negedge o_dac_sclk) begin
        if (!o_dac_sync_n) begin
            if (bit_idx < 16) begin
                captured_word[15 - bit_idx] = o_dac_sdin;
                bit_idx = bit_idx + 1;
            end
        end
    end

    // Проверка кадра по фронту o_dac_sync_n (окончание транзакции)
    always @(posedge o_dac_sync_n) begin
        if (bit_idx > 0) begin
            $display("[MONITOR] @ %0t ns: Передача кадра SPI завершена.", $time);
            $display("          Сырой кадр: 16'b%b (16'h%h)", captured_word, captured_word);
            $display("          Декодировано -> Режим: 4'b%b, Данные: 10'd%d (10'h%h)", 
                     captured_word[15:12], captured_word[11:2], captured_word[11:2]);
            
            // Самопроверка параметров кадра
            if (captured_word[15:12] !== TB_DAC_OP_MODE) begin
                $display("          [ОШИБКА] Несовпадение режима OP Mode! Ожидалось: 4'b%b, Получено: 4'b%b", TB_DAC_OP_MODE, captured_word[15:12]);
            end else begin
                $display("          [УСПЕХ] Режим OP Mode совпадает.");
            end
            
            // Младшие неиспользуемые биты [1:0] должны быть равны 0
            if (captured_word[1:0] !== 2'b00) begin
                $display("          [ОШИБКА] Младшие биты LSB не равны 2'b00! Получено: 2'b%b", captured_word[1:0]);
            end
            
            bit_idx = 0;
        end
    end

    // Таск для удобной передачи 10-битных данных
    task send_data(input [9:0] data);
        begin
            // Ожидание готовности передатчика
            while (!o_dac_data_rdy) begin
                @(posedge dac_clk);
            end
            
            // Выставление данных и строба валидности
            i_dac_data     <= data;
            i_dac_data_vld <= 1'b1;
            @(posedge dac_clk);
            
            // Снятие строба на следующем такте
            i_dac_data_vld <= 1'b0;
            @(posedge dac_clk);
        end
    endtask

    // Основной сценарий симуляции
    initial begin
        // Инициализация входных сигналов
        i_dac_data     = 10'd0;
        i_dac_data_vld = 1'b0;
        dac_rst_n      = 1'b0;

        // Настройка записи временных диаграмм (VCD)
        $dumpfile("dac_spi_tb.vcd");
        $dumpvars(0, dac_spi_tb);

        $display("[TB START] Инициализация теста модуля dac_spi.");
        #100;
        
        // Снятие асинхронного сброса
        @(posedge dac_clk);
        dac_rst_n = 1'b1;
        $display("[TB RESET] Сброс снят.");
        #100;

        // Тест 1: Передача стандартного значения средней шкалы
        $display("\n--- Тест 1: Передача 10'h1A5 (Среднее значение) ---");
        send_data(10'h1A5);
        
        // Ждем возврата в состояние готовности
        while (!o_dac_data_rdy) begin
            @(posedge dac_clk);
        end
        #200;

        // Тест 2: Передача максимального значения (Full Scale)
        $display("\n--- Тест 2: Передача 10'h3FF (Максимальное значение) ---");
        send_data(10'h3FF);
        
        while (!o_dac_data_rdy) begin
            @(posedge dac_clk);
        end
        #200;

        // Тест 3: Передача минимального значения (Zero Scale)
        $display("\n--- Тест 3: Передача 10'h000 (Минимальное значение) ---");
        send_data(10'h000);
        
        while (!o_dac_data_rdy) begin
            @(posedge dac_clk);
        end
        #200;

        // Тест 4: Передача паттерна типа "бегущая единица"
        $display("\n--- Тест 4: Передача 10'h2AA (Чередующийся паттерн) ---");
        send_data(10'h2AA);
        
        while (!o_dac_data_rdy) begin
            @(posedge dac_clk);
        end
        #200;

        // Тест 5: Непрерывная передача нескольких слов подряд (Back-to-Back)
        $display("\n--- Тест 5: Непрерывная отправка нескольких пакетов (Back-to-Back) ---");
        
        fork
            begin
                send_data(10'h111);
                send_data(10'h222);
                send_data(10'h333);
            end
            begin
                @(posedge i_dac_data_vld);
                $display("[TB] Конвейерная отправка запущена...");
            end
        join

        // Ожидание завершения всей очереди транзакций
        while (!o_dac_data_rdy) begin
            @(posedge dac_clk);
        end
        #500;

        // Тест 6: Проверка поведения во время асинхронного сброса
        $display("\n--- Тест 6: Аварийный сброс прямо во время активной транзакции ---");
        send_data(10'h1F0);
        
        // Ждем половины транзакции (примерно 15 тактов dac_clk)
        repeat (15) @(posedge dac_clk);
        
        $display("[TB] Активация сброса! dac_rst_n <= 0");
        dac_rst_n = 1'b0;
        #100;
        dac_rst_n = 1'b1;
        $display("[TB] Сброс снят. Модуль должен вернуться в IDLE, o_dac_data_rdy должен быть 1.");
        #100;

        $display("\n[TB END] Тестирование успешно завершено.");
        $finish;
    end

endmodule