`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Chuyen pulse giua 2 clock domain
//
// Cach hoat dong:
// - Source domain doi trang thai 1 toggle moi khi co i_src_pulse.
// - Destination domain dong bo toggle qua 2 FF.
// - So sanh toggle hien tai va toggle truoc do de tao pulse 1 chu ky dst clock.
//
// Luu y:
// - Chi dung cho event roi rac, khong dung cho data bus.
// - Event khong duoc den qua day den muc destination clock khong kip bat toggle.
//------------------------------------------------------------------------------
module eth_cdc_pulse (
    input  wire i_src_clk,
    input  wire i_src_rst_n,
    input  wire i_src_pulse,

    input  wire i_dst_clk,
    input  wire i_dst_rst_n,
    output wire o_dst_pulse
);

    reg r_src_toggle;

    always @(posedge i_src_clk or negedge i_src_rst_n) begin
        if (!i_src_rst_n)
            r_src_toggle <= 1'b0;
        else if (i_src_pulse)
            r_src_toggle <= ~r_src_toggle;
    end

    reg r_dst_sync_1;
    reg r_dst_sync_2;
    reg r_dst_toggle_d;

    always @(posedge i_dst_clk or negedge i_dst_rst_n) begin
        if (!i_dst_rst_n) begin
            r_dst_sync_1  <= 1'b0;
            r_dst_sync_2  <= 1'b0;
            r_dst_toggle_d <= 1'b0;
        end else begin
            r_dst_sync_1  <= r_src_toggle;
            r_dst_sync_2  <= r_dst_sync_1;
            r_dst_toggle_d <= r_dst_sync_2;
        end
    end

    assign o_dst_pulse = r_dst_sync_2 ^ r_dst_toggle_d;

endmodule
