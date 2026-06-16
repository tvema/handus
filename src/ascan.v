`timescale 1ns / 1ps

`include "def_param.h"

module ascan #(
    parameter ADDR_WIDTH = 11 // Глубина 2048 слов по 32 бита (вмещает до 5461 отсчетов)
) (
    // Домен системной частоты (sys_clk: 80 МГц)
    input                    sys_clk,        // Системная тактовая частота
    input                    sys_rst_n,      // Асинхронный сброс (sys_clk) с активным низким уровнем
    
    // Выходной интерфейс квитирования (домен sys_clk)
    output                   o_data_ready,   // Готовность буфера к чтению
    output reg [15:0]        o_out_size,     // Количество слов в буфере на момент появления готовности
    output [31:0]            o_out_data,     // Выход упакованных 32-битных слов
    output                   o_out_vld,      // Валидность выходных данных
    input                    i_out_rdy,      // Готовность приемника
    
    // Домен частоты АЦП (adc_clk: 65 МГц)
    input                    adc_clk,        // Тактовая частота АЦП
    input                    adc_rst_n,      // Асинхронный сброс (adc_clk) с активным низким уровнем
    input signed [11:0]      i_in_data,      // Входной поток 12-битных знаковых данных АЦП
    input                    i_adc_sync,     // Однотактовый импульс синхронизации запуска (adc_clk)
    input [15:0]             i_n_samples,    // Количество накапливаемых отсчетов (на частоте adc_clk)
    input [15:0]             i_skip_ticks,   // Количество пропускаемых тактов перед началом записи (на частоте adc_clk)
    input [7:0]              i_accum,        // Параметр "накопление" (на частоте adc_clk)
    input [3:0]              i_accum_type    // Параметр "тип накопления" (на частоте adc_clk)
);

    //--------------------------------------------------------------------------
    // 1. Захват параметров (домен adc_clk)
    //--------------------------------------------------------------------------
    reg [15:0] r_n_samples;
    reg [15:0] r_skip_ticks;
    reg [7:0]  r_accum;
    reg [3:0]  r_accum_type;

    // Защелкивание параметров по импульсу i_adc_sync в домене АЦП
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            r_n_samples  <= `INIT_ASCAN_N_SAMPLES;
            r_skip_ticks <= `INIT_ASCAN_DELAY_TIME;
            r_accum      <= `INIT_ASCAN_ACCUM;
            r_accum_type <= `INIT_ASCAN_ACCUM_TYPE;
        end else if (i_adc_sync) begin
            r_n_samples  <= i_n_samples;
            r_skip_ticks <= i_skip_ticks;
            r_accum      <= i_accum;
            r_accum_type <= i_accum_type;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Модуль начального преобразования данных (выделение максимума или среднего)
    //--------------------------------------------------------------------------
    wire signed [11:0] decim_data;
    wire               decim_vld;
    wire               decim_last = (sample_cnt == r_n_samples - 1);

    ascan_decimator u_decimator (
        .clk          (adc_clk),
        .rst_n        (adc_rst_n),
        .i_sync       (i_adc_sync),
        .i_active     (active),
        .i_last       (decim_last),
        .i_accum      (r_accum),
        .i_accum_type (r_accum_type),
        .i_data       (i_in_data),
        .o_data       (decim_data),
        .o_vld        (decim_vld)
    );

    //--------------------------------------------------------------------------
    // 3. Модуль упаковщика данных (домен adc_clk)
    //--------------------------------------------------------------------------
    reg         active;
    wire [31:0] fifo_wdata;
    wire        fifo_wen;

    ascan_packer u_packer (
        .adc_clk   (adc_clk),
        .rst_n     (adc_rst_n), // Используем сброс домена АЦП
        .i_sync_pe (i_adc_sync),
        .i_active  (active),
        .i_vld     (decim_vld),
        .i_data    (decim_data),
        .o_data    (fifo_wdata),
        .o_vld     (fifo_wen)
    );

    //--------------------------------------------------------------------------
    // 4. Управление записью в пинг-понг буферы (домен adc_clk)
    //--------------------------------------------------------------------------
    reg [15:0] sample_cnt;
    reg [15:0] wr_word_cnt;
    reg        wr_page;
    reg        write_done_toggle;
    
    // Регистры для фиксации размера накопленных 32-битных слов по страницам
    reg [15:0] ram_page_size_0;
    reg [15:0] ram_page_size_1;

    // Сигналы для реализации пропуска тактов перед стартом записи
    reg [15:0] skip_cnt;
    reg        skip_active;

    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            active            <= 1'b0;
            skip_active       <= 1'b0;
            skip_cnt          <= 16'd0;
            sample_cnt        <= 16'd0;
            wr_word_cnt       <= 16'd0;
            wr_page           <= 1'b0;
            write_done_toggle <= 1'b0;
            ram_page_size_0   <= 16'd0;
            ram_page_size_1   <= 16'd0;
        end else begin
            if (i_adc_sync && (i_n_samples > 0)) begin
                // Если задан пропуск тактов, переходим в состояние ожидания
                if (i_skip_ticks > 0) begin
                    skip_active <= 1'b1;
                    skip_cnt    <= i_skip_ticks;
                    active      <= 1'b0;
                end else begin
                    skip_active <= 1'b0;
                    active      <= 1'b1;
                end
                sample_cnt        <= 16'd0;
                wr_word_cnt       <= 16'd0;
            end else if (skip_active) begin
                // Отсчет тактов пропуска
                if (skip_cnt == 16'd1) begin
                    skip_active <= 1'b0;
                    active      <= 1'b1;
                end else begin
                    skip_cnt    <= skip_cnt - 1'b1;
                end
            end else if (active) begin
                sample_cnt <= sample_cnt + 1'b1;
                
                if (fifo_wen) begin
                    wr_word_cnt <= wr_word_cnt + 1'b1;
                end
                
                // Проверяем достижение заданного количества отсчетов АЦП
                if (sample_cnt == r_n_samples - 1) begin
                    active <= 1'b0;
                    
                    // Сохраняем реальное количество записанных 32-битных слов
                    // (с учетом флага fifo_wen на текущем такте)
                    if (wr_page == 1'b0)
                        ram_page_size_0 <= wr_word_cnt + fifo_wen;
                    else
                        ram_page_size_1 <= wr_word_cnt + fifo_wen;
                        
                    wr_page           <= ~wr_page;
                    write_done_toggle <= ~write_done_toggle;
                end
            end
        end
    end

    // Маршрутизация сигналов записи в буферы памяти
    wire ram0_wr_en = fifo_wen && (wr_page == 1'b0);
    wire ram1_wr_en = fifo_wen && (wr_page == 1'b1);

    //--------------------------------------------------------------------------
    // 5. Блок двухпортовой памяти (буферы "бабочка")
    //--------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] ram_rd_addr;
    wire                  ram_rd_en;
    wire [31:0]           ram0_rd_data;
    wire [31:0]           ram1_rd_data;
    reg                   rd_page;

    // Buffer 0 (RAM_0)
    ascan_dpram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_ram0 (
        .i_wr_clk  (adc_clk),
        .i_wr_en   (ram0_wr_en),
        .i_wr_addr (wr_word_cnt[ADDR_WIDTH-1:0]),
        .i_wr_data (fifo_wdata),

        .i_rd_clk  (sys_clk),
        .i_rd_en   (ram_rd_en && (rd_page == 1'b0)),
        .i_rd_addr (ram_rd_addr),
        .o_rd_data (ram0_rd_data)
    );

    // Buffer 1 (RAM_1)
    ascan_dpram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_ram1 (
        .i_wr_clk  (adc_clk),
        .i_wr_en   (ram1_wr_en),
        .i_wr_addr (wr_word_cnt[ADDR_WIDTH-1:0]),
        .i_wr_data (fifo_wdata),

        .i_rd_clk  (sys_clk),
        .i_rd_en   (ram_rd_en && (rd_page == 1'b1)),
        .i_rd_addr (ram_rd_addr),
        .o_rd_data (ram1_rd_data)
    );

    //--------------------------------------------------------------------------
    // 6. Междоменный переход (CDC) и учет страниц (домен sys_clk)
    //--------------------------------------------------------------------------
    reg wr_done_sync0, wr_done_sync1, wr_done_sync2;
    
    // Синхронизация флага окончания записи в домен sys_clk
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr_done_sync0 <= 1'b0;
            wr_done_sync1 <= 1'b0;
            wr_done_sync2 <= 1'b0;
        end else begin
            wr_done_sync0 <= write_done_toggle;
            wr_done_sync1 <= wr_done_sync0;
            wr_done_sync2 <= wr_done_sync1;
        end
    end

    wire wr_done_edge = wr_done_sync1 ^ wr_done_sync2;

    reg [1:0] pages_avail;
    reg       read_done;

    // Счетчик готовых страниц в памяти
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            pages_avail <= 2'b00;
        end else begin
            case ({wr_done_edge, read_done})
                2'b10:   pages_avail <= pages_avail + 1'b1;
                2'b01:   pages_avail <= pages_avail - 1'b1;
                2'b11:   pages_avail <= pages_avail;
                default: ;
            endcase
        end
    end

    assign o_data_ready = (pages_avail > 0);

    // Определение размера текущей готовой к чтению страницы
    wire [15:0] current_page_size = (rd_page == 1'b0) ? ram_page_size_0 : ram_page_size_1;

    reg                  read_active;

    // Фиксация количества слов в буфере на момент появления готовности
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            o_out_size <= 16'd0;
        end else if (!read_active && (pages_avail > 0)) begin
            // Размер стабилен в течение всего цикла чтения страницы
            o_out_size <= current_page_size;
        end
    end

    //--------------------------------------------------------------------------
    // 7. Выходной автомат управления квитированием (домен sys_clk)
    //--------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] rd_addr;
    reg                  out_vld;
    reg [31:0]           out_data;
    reg                  ram_read_en_d1;
    reg [15:0]           words_out_cnt;

    wire [31:0] current_ram_data = (rd_page == 1'b0) ? ram0_rd_data : ram1_rd_data;
    
    assign ram_rd_addr = rd_addr;
    assign ram_rd_en   = read_active && (!out_vld || i_out_rdy) && (rd_addr < o_out_size[ADDR_WIDTH-1:0]);

    assign o_out_vld   = out_vld;
    assign o_out_data  = out_data;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rd_addr        <= 0;
            read_active    <= 1'b0;
            rd_page        <= 1'b0;
            read_done      <= 1'b0;
            out_vld        <= 1'b0;
            out_data       <= 32'd0;
            ram_read_en_d1 <= 1'b0;
            words_out_cnt  <= 16'd0;
        end else begin
            read_done <= 1'b0;

            if (i_out_rdy) begin
                out_vld <= 1'b0;
            end

            // Старт чтения новой страницы памяти
            if (!read_active && (pages_avail > 0)) begin
                read_active   <= 1'b1;
                rd_addr       <= 0;
                words_out_cnt <= 16'd0;
            end

            if (ram_rd_en) begin
                rd_addr <= rd_addr + 1'b1;
            end

            ram_read_en_d1 <= ram_rd_en;

            // Чтение данных из памяти и фиксация на выходе
            if (ram_read_en_d1) begin
                out_data <= current_ram_data;
                out_vld  <= 1'b1;
            end else if (i_out_rdy) begin
                out_vld  <= 1'b0;
            end

            // Квитирование и завершение транзакции
            if (read_active) begin
                if (out_vld && i_out_rdy) begin
                    words_out_cnt <= words_out_cnt + 1'b1;
                    if (words_out_cnt == o_out_size - 1) begin
                        read_active   <= 1'b0;
                        rd_page       <= ~rd_page;
                        read_done     <= 1'b1;
                    end
                end
            end
        end
    end

endmodule

//--------------------------------------------------------------------------
// Вспомогательный модуль: Прореживание знаковых данных со знаковыми/модульными режимами
//--------------------------------------------------------------------------
module ascan_decimator (
    input                     clk,          // Тактовая частота АЦП (adc_clk)
    input                     rst_n,        // Асинхронный сброс (активный низкий)
    input                     i_sync,       // Импульс синхронизации запуска
    input                     i_active,     // Флаг активности сбора
    input                     i_last,       // Сигнал последнего отсчета всей пачки
    input [7:0]               i_accum,      // Коэффициент прореживания (N)
    input [3:0]               i_accum_type, // Тип накопления (1 - макс по модулю со знаком, 2 - среднее по модулю, 3 - макс по модулю без знака)
    input signed [11:0]       i_data,       // Входной 12-битный знаковый поток данных АЦП
    output reg signed [11:0]  o_data,       // Выходное вычисленное значение (знаковое)
    output reg                o_vld         // Флаг валидности выходного значения
);

    reg [7:0]                 cnt;
    reg [11:0]                max_abs_val;       // Максимальное абсолютное значение (беззнаковое)
    reg signed [11:0]         max_val_with_sign;  // Соответствующий отсчет с сохранением знака
    reg [19:0]                sum_abs_val;       // Накопленная сумма абсолютных значений

    // Вычисление абсолютного значения с насыщением для -2048 (чтобы поместилось в 11 бит положительной сетки)
    wire [11:0] cur_abs_in = (i_data == 12'sh800) ? 12'd2047 :
                             (i_data[11] ? (~i_data + 1'b1) : i_data);

    // Определение текущего локального максимума по модулю
    wire [11:0] cur_max_abs = (cnt == 8'd0) ? cur_abs_in :
                              ((cur_abs_in > max_abs_val) ? cur_abs_in : max_abs_val);

    // Фиксация отсчета с оригинальным знаком, имеющего максимальный модуль
    wire signed [11:0] cur_val_with_sign = (cnt == 8'd0) ? i_data :
                                            ((cur_abs_in > max_abs_val) ? i_data : max_val_with_sign);

    // Накопление текущей суммы абсолютных значений
    wire [19:0] cur_sum_abs = (cnt == 8'd0) ? {8'b0, cur_abs_in} :
                              (sum_abs_val + cur_abs_in);

    // Определение фактического делителя (для защиты от неполной пачки в конце кадра по i_last)
    wire [7:0]  divisor = ((cnt == i_accum - 8'd1) || (i_accum == 8'd0)) ? i_accum : (cnt + 8'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt               <= 8'd0;
            max_abs_val       <= 12'd0;
            max_val_with_sign <= 12'sd0;
            sum_abs_val       <= 20'd0;
            o_data            <= 12'sd0;
            o_vld             <= 1'b0;
        end else begin
            o_vld <= 1'b0;
            if (i_sync) begin
                cnt               <= 8'd0;
                max_abs_val       <= 12'd0;
                max_val_with_sign <= 12'sd0;
                sum_abs_val       <= 20'd0;
            end else if (i_active) begin
                if (i_accum <= 8'd1) begin
                    // Без накопления: просто пропускаем знаковые данные напрямую
                    o_data <= i_data;
                    o_vld  <= 1'b1;
                end else begin
                    max_abs_val       <= cur_max_abs;
                    max_val_with_sign <= cur_val_with_sign;
                    sum_abs_val       <= cur_sum_abs;

                    // Выдача данных по завершению пачки накопления или на самом последнем отсчете пачки
                    if ((cnt == i_accum - 8'd1) || i_last) begin
                        case (i_accum_type)
                            4'd2: begin
                                // Тип накопления 2: Среднее по модулю (всегда положительное)
                                if (divisor > 8'd0) begin
                                    o_data <= $signed({1'b0, cur_sum_abs / divisor});
                                end else begin
                                    o_data <= $signed({1'b0, cur_abs_in});
                                end
                            end
                            
                            4'd3: begin
                                // Тип накопления 3: Максимум по модулю без восстановления знака
                                o_data <= $signed({1'b0, cur_max_abs});
                            end
                            
                            default: begin
                                // Тип накопления 1 (и по умолчанию): Максимум по модулю с восстановлением знака
                                o_data <= cur_val_with_sign;
                            end
                        endcase
                        o_vld  <= 1'b1;
                        cnt    <= 8'd0;
                    end else begin
                        cnt    <= cnt + 1'b1;
                    end
                end
            end else begin
                cnt <= 8'd0;
            end
        end
    end

endmodule

//--------------------------------------------------------------------------
// Вспомогательный модуль: Упаковщик данных (из 12-битного потока в 32-битные слова)
//--------------------------------------------------------------------------
module ascan_packer (
    input             adc_clk,      // Входная тактовая частота
    input             rst_n,        // Асинхронный сброс
    input             i_sync_pe,    // Импульс синхронизации начала
    input             i_active,     // Разрешение упаковки
    input             i_vld,        // Флаг валидности входных данных
    input [11:0]      i_data,       // Входной 12-битный поток
    output reg [31:0] o_data,       // Выходное упакованное 32-битное слово
    output reg        o_vld         // Разрешение записи (строб валидности слова)
);

    reg [27:0] bit_buf;             // Накопительный буфер остатка бит
    reg [5:0]  bit_cnt;             // Количество значащих бит в буфере

    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_buf <= 28'd0;
            bit_cnt <= 6'd0;
            o_data  <= 32'd0;
            o_vld   <= 1'b0;
        end else if (i_active) begin
            if (i_vld) begin
                case (bit_cnt)
                    6'd0: begin
                        bit_buf[11:0] <= i_data;
                        bit_cnt       <= 6'd12;
                        o_vld         <= 1'b0;
                    end
                    
                    6'd12: begin
                        bit_buf[23:12] <= i_data;
                        bit_cnt        <= 6'd24;
                        o_vld          <= 1'b0;
                    end
                    
                    6'd24: begin
                        o_data        <= {i_data[7:0], bit_buf[23:0]};
                        o_vld         <= 1'b1;
                        bit_buf[3:0]  <= i_data[11:8];
                        bit_cnt       <= 6'd4;
                    end
                    
                    6'd4: begin
                        bit_buf[15:4] <= i_data;
                        bit_cnt       <= 6'd16;
                        o_vld         <= 1'b0;
                    end
                    
                    6'd16: begin
                        bit_buf[27:16] <= i_data;
                        bit_cnt        <= 6'd28;
                        o_vld          <= 1'b0;
                    end
                    
                    6'd28: begin
                        o_data        <= {i_data[3:0], bit_buf[27:0]};
                        o_vld         <= 1'b1;
                        bit_buf[7:0]  <= i_data[11:4];
                        bit_cnt       <= 6'd8;
                    end
                    
                    6'd8: begin
                        bit_buf[19:8] <= i_data;
                        bit_cnt       <= 6'd20;
                        o_vld         <= 1'b0;
                    end
                    
                    6'd20: begin
                        o_data        <= {i_data, bit_buf[19:0]};
                        o_vld         <= 1'b1;
                        bit_cnt       <= 6'd0;
                    end
                    
                    default: begin
                        bit_cnt <= 6'd0;
                        o_vld   <= 1'b0;
                    end
                endcase
            end else begin
                o_vld <= 1'b0;
            end
        end else begin
            o_vld <= 1'b0;
            if (i_sync_pe) begin
                bit_cnt <= 6'd0;
            end
        end
    end

endmodule

//--------------------------------------------------------------------------
// Вспомогательный модуль: Двухпортовое ОЗУ с заглушкой для TESTMODE
//--------------------------------------------------------------------------
module ascan_dpram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 11
) (
    input                     i_wr_clk,
    input                     i_wr_en,
    input  [ADDR_WIDTH-1:0]   i_wr_addr,
    input  [DATA_WIDTH-1:0]   i_wr_data,

    input                     i_rd_clk,
    input                     i_rd_en,
    input  [ADDR_WIDTH-1:0]   i_rd_addr,
    output [DATA_WIDTH-1:0]   o_rd_data
);

`ifdef TESTMODE
    // Поведенческая симуляционная модель ОЗУ
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    reg [DATA_WIDTH-1:0] r_rd_data;
    
    assign o_rd_data = r_rd_data;
    
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            ram[i] = i; 
        end
    end

    always @(posedge i_wr_clk) begin
        if (i_wr_en) begin
            ram[i_wr_addr] <= i_wr_data;
        end
    end

    always @(posedge i_rd_clk) begin
        if (i_rd_en) begin
            r_rd_data <= ram[i_rd_addr];
        end
    end
`else
    // Физическая двухпортовая память Quartus FPGA (M10K/M20K)
    altsyncram #(
        .address_reg_b("CLOCK1"),
        .clock_enable_input_a("BYPASS"),
        .clock_enable_input_b("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .lpm_type("altsyncram"),
        .numwords_a(1 << ADDR_WIDTH),
        .numwords_b(1 << ADDR_WIDTH),
        .operation_mode("DUAL_PORT"),
        .outdata_aclr_b("NONE"),
        .outdata_reg_b("UNREGISTERED"),
        .power_up_uninitialized("FALSE"),
        .rdcontrol_reg_b("CLOCK1"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .widthad_a(ADDR_WIDTH),
        .widthad_b(ADDR_WIDTH),
        .width_a(DATA_WIDTH),
        .width_b(DATA_WIDTH),
        .width_byteena_a(1)
    ) altsyncram_component (
        .address_a (i_wr_addr),
        .address_b (i_rd_addr),
        .clock0 (i_wr_clk),
        .clock1 (i_rd_clk),
        .data_a (i_wr_data),
        .wren_a (i_wr_en),
        .rden_b (i_rd_en),
        .q_b (o_rd_data),
        .aclr0 (1'b0),
        .aclr1 (1'b0),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a (1'b1),
        .byteena_b (1'b1),
        .clocken0 (1'b1),
        .clocken1 (1'b1),
        .clocken2 (1'b1),
        .clocken3 (1'b1),
        .data_b ({DATA_WIDTH{1'b0}}),
        .eccstatus (),
        .q_a (),
        .wren_b (1'b0)
    );
`endif

endmodule