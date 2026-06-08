// src/param.v

`default_nettype none

module param (
    // Clocks
    input  wire        sys_clk,
    input  wire        adc_clk,
    input  wire        log_clk,
    input  wire        dac_clk,
    input  wire        hi_clk,

    // Reset
    input  wire        rst_n,

    // Input command stream (on sys_clk)
    input  wire        i_cmd_val,
    input  wire [31:0] i_cmd_addr,
    input  wire [31:0] i_cmd_data,

    // Outputs for Domain 1 (sys_clk)
    output reg         o_sys_cmd_val,
    output reg  [31:0] o_sys_cmd_addr,
    output reg  [31:0] o_sys_cmd_data,

    // Outputs for Domain 2 (adc_clk)
    output wire        o_adc_cmd_val,
    output wire [31:0] o_adc_cmd_addr,
    output wire [31:0] o_adc_cmd_data,

    // Outputs for Domain 3 (log_clk)
    output wire        o_log_cmd_val,
    output wire [31:0] o_log_cmd_addr,
    output wire [31:0] o_log_cmd_data,

    // Outputs for Domain 4 (dac_clk)
    output wire        o_dac_cmd_val,
    output wire [31:0] o_dac_cmd_addr,
    output wire [31:0] o_dac_cmd_data,

    // Outputs for Domain 5 (hi_clk)
    output wire        o_hi_cmd_val,
    output wire [31:0] o_hi_cmd_addr,
    output wire [31:0] o_hi_cmd_data
);

    // Декодирование адресов назначения (по старшему байту)
    wire cmd_to_sys = i_cmd_val && (i_cmd_addr[31:24] == 8'h01);
    wire cmd_to_adc = i_cmd_val && (i_cmd_addr[31:24] == 8'h02);
    wire cmd_to_log = i_cmd_val && (i_cmd_addr[31:24] == 8'h03);
    wire cmd_to_dac = i_cmd_val && (i_cmd_addr[31:24] == 8'h04);
    wire cmd_to_hi  = i_cmd_val && (i_cmd_addr[31:24] == 8'h05);

    //--------------------------------------------------------------------------
    // Обработка команд на локальной частоте sys_clk (Domain 1)
    //--------------------------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            o_sys_cmd_val  <= 1'b0;
            o_sys_cmd_addr <= 32'd0;
            o_sys_cmd_data <= 32'd0;
        end else begin
            if (cmd_to_sys) begin
                o_sys_cmd_val  <= 1'b1;
                o_sys_cmd_addr <= i_cmd_addr;
                o_sys_cmd_data <= i_cmd_data;
            end else begin
                o_sys_cmd_val  <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Передача команд на частоту adc_clk (Domain 2)
    //--------------------------------------------------------------------------
    param_cdc_fifo u_cdc_adc (
        .src_clk   (sys_clk),
        .src_rst_n (rst_n),
        .src_valid (cmd_to_adc),
        .src_addr  (i_cmd_addr),
        .src_data  (i_cmd_data),

        .dst_clk   (adc_clk),
        .dst_rst_n (rst_n),
        .dst_valid (o_adc_cmd_val),
        .dst_addr  (o_adc_cmd_addr),
        .dst_data  (o_adc_cmd_data)
    );

    //--------------------------------------------------------------------------
    // Передача команд на частоту log_clk (Domain 3)
    //--------------------------------------------------------------------------
    param_cdc_fifo u_cdc_log (
        .src_clk   (sys_clk),
        .src_rst_n (rst_n),
        .src_valid (cmd_to_log),
        .src_addr  (i_cmd_addr),
        .src_data  (i_cmd_data),

        .dst_clk   (log_clk),
        .dst_rst_n (rst_n),
        .dst_valid (o_log_cmd_val),
        .dst_addr  (o_log_cmd_addr),
        .dst_data  (o_log_cmd_data)
    );

    //--------------------------------------------------------------------------
    // Передача команд на частоту dac_clk (Domain 4)
    //--------------------------------------------------------------------------
    param_cdc_fifo u_cdc_dac (
        .src_clk   (sys_clk),
        .src_rst_n (rst_n),
        .src_valid (cmd_to_dac),
        .src_addr  (i_cmd_addr),
        .src_data  (i_cmd_data),

        .dst_clk   (dac_clk),
        .dst_rst_n (rst_n),
        .dst_valid (o_dac_cmd_val),
        .dst_addr  (o_dac_cmd_addr),
        .dst_data  (o_dac_cmd_data)
    );

    //--------------------------------------------------------------------------
    // Передача команд на частоту hi_clk (Domain 5)
    //--------------------------------------------------------------------------
    param_cdc_fifo u_cdc_hi (
        .src_clk   (sys_clk),
        .src_rst_n (rst_n),
        .src_valid (cmd_to_hi),
        .src_addr  (i_cmd_addr),
        .src_data  (i_cmd_data),

        .dst_clk   (hi_clk),
        .dst_rst_n (rst_n),
        .dst_valid (o_hi_cmd_val),
        .dst_addr  (o_hi_cmd_addr),
        .dst_data  (o_hi_cmd_data)
    );

endmodule


//==============================================================================
// Вспомогательный модуль для безопасного кроссдоменного переноса параметров
//==============================================================================
module param_cdc_fifo (
    input  wire        src_clk,
    input  wire        src_rst_n,
    input  wire        src_valid,
    input  wire [31:0] src_addr,
    input  wire [31:0] src_data,

    input  wire        dst_clk,
    input  wire        dst_rst_n,
    output reg         dst_valid,
    output wire [31:0] dst_addr,
    output wire [31:0] dst_data
);

    wire        fifo_empty;
    wire [63:0] fifo_rd_data;
    wire        fifo_rd_en = !fifo_empty;

    // Асинхронное FIFO глубиной 8 элементов для безопасной передачи шины
    param_async_fifo #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (3)
    ) u_async_fifo (
        .wr_clk   (src_clk),
        .wr_rst_n (src_rst_n),
        .wr_en    (src_valid),
        .wr_data  ({src_addr, src_data}),
        .wr_full  (), // Игнорируем переполнение, т.к. темп команд существенно ниже частот

        .rd_clk   (dst_clk),
        .rd_rst_n (dst_rst_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .rd_empty (fifo_empty)
    );

    assign dst_addr = fifo_rd_data[63:32];
    assign dst_data = fifo_rd_data[31:0];

    // Формирование валидации на выходе целевого домена
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_valid <= 1'b0;
        end else begin
            dst_valid <= fifo_rd_en;
        end
    end

endmodule


//==============================================================================
// Простая и надежная реализация асинхронного FIFO на коде Грея
//==============================================================================
module param_async_fifo #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 3
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0]   wr_ptr;
    reg [ADDR_WIDTH:0]   rd_ptr;

    // Перевод указателей в код Грея
    wire [ADDR_WIDTH:0] wr_ptr_gray = wr_ptr ^ (wr_ptr >> 1);
    wire [ADDR_WIDTH:0] rd_ptr_gray = rd_ptr ^ (rd_ptr >> 1);

    // Регистры синхронизации указателей между доменами частот
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Синхронизация wr_ptr во временной домен rd_clk
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= {(ADDR_WIDTH+1){1'b0}};
            wr_ptr_gray_sync2 <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // Синхронизация rd_ptr во временной домен wr_clk
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= {(ADDR_WIDTH+1){1'b0}};
            rd_ptr_gray_sync2 <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Запись в память FIFO
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else if (wr_en && !wr_full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Чтение из памяти FIFO
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else if (rd_en && !rd_empty) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    // Генерация флагов Full и Empty на основе кодов Грея
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
    assign wr_full  = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

endmodule

`default_nettype wire