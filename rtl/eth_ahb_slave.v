`timescale 1ns/1ps

//------------------------------------------------------------------------------
// AHB-Lite slave cho Ethernet MAC buffer-based
//
// Nhiem vu:
// - Nhan access AHB tu CPU.
// - Chi chap nhan access 32-bit word, dia chi aligned 4 byte.
// - Chi chap nhan register window 0x00..0xFF.
// - Doi access AHB hop le thanh read/write cho eth_register.
// - Tra AHB ERROR neu size/alignment/address sai hoac register bao loi.
//
// Luu y:
// - Dia chi AHB trong IP nay la 10-bit, giong RTL cu.
// - BD/DMA window da bi bo.
// - Dia chi khong co register trong 0x00..0xFF la reserved:
//   van dua sang eth_register de doc 0/ghi bo qua.
// - HTRANS IDLE/BUSY la no-op OKAY, NONSEQ/SEQ la access.
// - Burst duoc chap nhan theo tung beat; master phai cap HADDR cua moi beat.
//------------------------------------------------------------------------------
module eth_ahb_slave #(
    parameter DATA_WIDTH = 32
) (
    input  wire                  i_HCLK,
    input  wire                  i_HRESET_n,

    input  wire [9:0]            i_HADDR,
    input  wire [1:0]            i_HTRANS,
    input  wire                  i_HWRITE,
    input  wire [2:0]            i_HSIZE,
    input  wire [2:0]            i_HBURST,
    input  wire [DATA_WIDTH-1:0] i_HWDATA,

    input  wire                  i_HSEL,
    input  wire                  i_HREADY,

    output reg  [DATA_WIDTH-1:0] o_HRDATA,
    output reg                   o_HREADYOUT,
    output reg                   o_HRESP,

    output reg                   o_reg_wr_en,
    output reg                   o_reg_rd_en,
    output reg  [7:0]            o_reg_addr,
    output reg  [DATA_WIDTH-1:0] o_reg_wdata,

    input  wire [DATA_WIDTH-1:0] i_reg_rdata,
    input  wire                  i_reg_error
);

    //--------------------------------------------------------------------------
    // Hang so AHB
    //--------------------------------------------------------------------------
    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;
    localparam [1:0] HTRANS_SEQ    = 2'b11;
    localparam [2:0] HSIZE_WORD    = 3'b010;

    localparam       HRESP_OKAY    = 1'b0;
    localparam       HRESP_ERROR   = 1'b1;

    //--------------------------------------------------------------------------
    // Address phase
    //--------------------------------------------------------------------------
    wire w_htrans_noop = (i_HTRANS == HTRANS_IDLE) |
                         (i_HTRANS == HTRANS_BUSY);
    wire w_htrans_access = (i_HTRANS == HTRANS_NONSEQ) |
                           (i_HTRANS == HTRANS_SEQ);
    wire w_addr_phase_valid = i_HSEL & ~w_htrans_noop & w_htrans_access;

    reg [9:0] r_addr;
    reg       r_write;
    reg [2:0] r_size;
    reg       r_valid;

    // 0x00..0xFF hop le, nen 2 bit dia chi cao [9:8] phai bang 0.
    wire w_addr_in_window = (r_addr[9:8] == 2'b00);
    wire w_addr_aligned   = (r_addr[1:0] == 2'b00);
    wire w_size_word      = (r_size == HSIZE_WORD);
    wire w_addr_ok        = w_addr_in_window & w_addr_aligned & w_size_word;

    // ERROR AHB-Lite co 2 chu ky:
    // - Chu ky dau: HREADYOUT=0, HRESP=ERROR.
    // - Chu ky sau: HREADYOUT=1, HRESP=ERROR.
    reg  r_error_second;
    wire w_reg_access = r_valid & w_addr_ok & ~r_error_second & i_HREADY;
    wire w_reg_error_first = w_reg_access & i_reg_error;
    wire w_error_first = r_valid & ~r_error_second &
                         (~w_addr_ok | w_reg_error_first);

    // Khong chot address moi trong chu ky dau cua ERROR, vi bus dang bi stall.
    // Chu ky ERROR thu hai co HREADYOUT=1 nen co the chot transfer ke tiep.
    wire w_capture_addr = i_HREADY & ~w_error_first;

    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n) begin
            r_addr  <= 10'd0;
            r_write <= 1'b0;
            r_size  <= 3'd0;
            r_valid <= 1'b0;
        end else if (w_capture_addr) begin
            r_addr  <= i_HADDR;
            r_write <= i_HWRITE;
            r_size  <= i_HSIZE;
            r_valid <= w_addr_phase_valid;
        end
    end

    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n)
            r_error_second <= 1'b0;
        else if (w_error_first)
            r_error_second <= 1'b1;
        else if (r_error_second & i_HREADY)
            r_error_second <= 1'b0;
    end

    //--------------------------------------------------------------------------
    // Register access trong data phase
    //--------------------------------------------------------------------------
    always @(*) begin
        o_reg_wr_en = w_reg_access & r_write;
        o_reg_rd_en = w_reg_access & ~r_write;
        o_reg_addr  = {2'b00, r_addr[7:2]};
        o_reg_wdata = i_HWDATA;
    end

    //--------------------------------------------------------------------------
    // AHB response
    //--------------------------------------------------------------------------
    always @(*) begin
        if (w_error_first) begin
            o_HREADYOUT = 1'b0;
            o_HRESP     = HRESP_ERROR;
        end else if (r_error_second) begin
            o_HREADYOUT = 1'b1;
            o_HRESP     = HRESP_ERROR;
        end else begin
            o_HREADYOUT = 1'b1;
            o_HRESP     = HRESP_OKAY;
        end
    end

    always @(*) begin
        if (w_reg_access & ~r_write)
            o_HRDATA = i_reg_rdata;
        else
            o_HRDATA = {DATA_WIDTH{1'b0}};
    end

    // i_HBURST khong tao dia chi noi bo. Neu master chay burst, slave xu ly
    // tung beat NONSEQ/SEQ theo HADDR ma master dua vao.
    wire w_unused_hburst = |i_HBURST;

endmodule
