`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Dong bo level tu clock nguon sang clock dich bang 2 FF.
// Chi dung cho status/config doi cham. Khong dung cho pulse hoac data handshake.
//------------------------------------------------------------------------------
module eth_sync_level #(
    parameter WIDTH = 1,
    parameter [127:0] RESET_VALUE = 128'd0
) (
    input  wire                  i_dst_clk,
    input  wire                  i_dst_rst_n,
    input  wire [WIDTH-1:0]      i_src_level,
    output wire [WIDTH-1:0]      o_dst_level
);

    reg [WIDTH-1:0] r_sync_1;
    reg [WIDTH-1:0] r_sync_2;

    always @(posedge i_dst_clk or negedge i_dst_rst_n) begin
        if (!i_dst_rst_n) begin
            r_sync_1 <= RESET_VALUE[WIDTH-1:0];
            r_sync_2 <= RESET_VALUE[WIDTH-1:0];
        end else begin
            r_sync_1 <= i_src_level;
            r_sync_2 <= r_sync_1;
        end
    end

    assign o_dst_level = r_sync_2;

endmodule
