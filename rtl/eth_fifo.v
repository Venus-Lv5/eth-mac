`timescale 1ns/1ps

module eth_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 16
)(
    // Global
    input wire                  i_clk,
    input wire                  i_rst_n,

    // Control
    input wire                  i_wr_en,
    input wire                  i_rd_en,
    input wire                  i_clear,

    // Data
    input wire  [DATA_WIDTH-1:0] i_din,
    output reg  [DATA_WIDTH-1:0] o_dout,

    // Status
    output wire                 o_empty,
    output wire                 o_full,
    output wire                 o_almost_empty,
    output wire                 o_almost_full,

    // Count
    output wire [$clog2(DEPTH):0] o_count
);

    localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam CNT_WIDTH  = ADDR_WIDTH + 1;

    reg [CNT_WIDTH-1:0]     r_wptr;
    reg [CNT_WIDTH-1:0]     r_rptr;
    reg [DATA_WIDTH-1:0]    r_mem [0:DEPTH-1];

    wire                    w_wr;
    wire                    w_rd;
    wire                    w_fbit_comp;
    wire                    w_pointer_equal;

    assign w_wr = i_wr_en & (~o_full | i_rd_en) & ~i_clear;

    assign w_rd = i_rd_en & ~o_empty & ~i_clear;

    assign w_fbit_comp     = r_wptr[ADDR_WIDTH] ^ r_rptr[ADDR_WIDTH];
    assign w_pointer_equal = r_wptr[ADDR_WIDTH-1:0] == r_rptr[ADDR_WIDTH-1:0];

    assign o_full  =  w_fbit_comp & w_pointer_equal;
    assign o_empty = ~w_fbit_comp & w_pointer_equal;

    assign o_count = r_wptr - r_rptr;

    assign o_almost_empty = (o_count <= 1);
    assign o_almost_full  = (o_count >= (DEPTH - 1));

    // Write pointer
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_wptr <= {CNT_WIDTH{1'b0}};
        else if (i_clear)
            r_wptr <= {CNT_WIDTH{1'b0}};   // FIX: clear sạch, không ghi lẫn
        else if (w_wr)
            r_wptr <= r_wptr + 1'b1;
    end

    // Read pointer
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rptr <= {CNT_WIDTH{1'b0}};
        else if (i_clear)
            r_rptr <= {CNT_WIDTH{1'b0}};
        else if (w_rd)
            r_rptr <= r_rptr + 1'b1;
    end

    // Memory write
    always @(posedge i_clk) begin
        if (w_wr)
            r_mem[r_wptr[ADDR_WIDTH-1:0]] <= i_din;
    end

    // Data output
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_dout <= {DATA_WIDTH{1'b0}};
        else if (i_clear)
            o_dout <= {DATA_WIDTH{1'b0}}; 
        else if (w_rd)
            o_dout <= r_mem[r_rptr[ADDR_WIDTH-1:0]];
    end

endmodule