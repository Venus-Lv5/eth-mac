`timescale 1ns/1ps

module eth_fifo #(
    parameter DATA_WIDTH    = 32,
    parameter DEPTH         = 16,
    parameter CNT_WIDTH     = 5
)(
    // Global
    input wire                  i_clk,
    input wire                  i_rst_n,
    
    // Control
    input wire                  i_wr_en,
    input wire                  i_rd_en,
    input wire                  i_clear,

    // Data
    input wire [DATA_WIDTH-1:0] i_din,
    output reg [DATA_WIDTH-1:0] o_dout,


    // Status
    output wire                 o_empty,
    output wire                 o_full,
    output wire                 o_almost_empty,
    output wire                 o_almost_full,

    //Count
    output reg [CNT_WIDTH-1:0]  o_count
)

