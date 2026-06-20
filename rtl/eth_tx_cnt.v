`timescale 1ns / 1ps

// eth_tx_cnt.v
// TX counters for IEEE 802.3 CSMA/CD transmission
// Based on ethmac eth_txcounters.v
// Buffer-based version:
// - Min frame and max frame are fixed.
// - i_st_data[0] is low nibble of current byte.
// - i_st_data[1] is high nibble of current byte.

module eth_tx_cnt (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // State signals from TX state machine
    input  wire        i_st_preamble,
    input  wire        i_st_ipg,
    input  wire [1:0]  i_st_data,
    input  wire        i_st_pad,
    input  wire        i_st_fcs,
    input  wire        i_st_jam,
    input  wire        i_st_backoff,
    input  wire        i_st_defer,
    input  wire        i_st_idle,

    // State transition signals
    input  wire        i_start_defer,
    input  wire        i_start_ipg,
    input  wire        i_start_fcs,
    input  wire        i_start_jam,
    input  wire        i_start_backoff,

    // Control signals
    input  wire        i_tx_start_frm,
    input  wire        i_packet_finished_q,

    // Outputs
    output wire [15:0] o_byte_cnt,
    output wire [15:0] o_nib_cnt,
    output wire        o_nib_eq_7,
    output wire        o_nib_eq_15,
    output wire        o_nib_min_fl,
    output wire        o_byte_max,
    output wire        o_excessive_defer
);

    // Fixed parameters.
    parameter [15:0] MIN_FL = 16'd64;
    parameter [15:0] MAX_FL = 16'd1518;
    parameter [13:0] EXCESSIVE_DEF_CNT = 14'h17B7;

    wire w_data_any  = |i_st_data;
    wire w_data_high = i_st_data[1];

    //============================================================
    // Nibble counter
    //============================================================
    wire w_nib_inc = i_st_ipg | i_st_preamble | w_data_any | i_st_pad
                   | i_st_fcs | i_st_jam | i_st_backoff
                   | (i_st_defer & ~o_excessive_defer & i_tx_start_frm);

    wire w_nib_rst = (i_st_defer & o_excessive_defer & ~i_tx_start_frm)
                   | (i_st_preamble & o_nib_eq_15)
                   | (i_st_jam & o_nib_eq_7)
                   | i_st_idle | i_start_defer | i_start_ipg | i_start_fcs | i_start_jam;

    reg [15:0] r_nib_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_nib_cnt <= 16'd0;
        else if (w_nib_rst)
            r_nib_cnt <= 16'd0;
        else if (w_nib_inc)
            r_nib_cnt <= r_nib_cnt + 16'd1;
    end

    assign o_nib_cnt = r_nib_cnt;

    // Nibble counter flags
    assign o_nib_eq_7  = &r_nib_cnt[2:0];   // NibCnt == 7
    assign o_nib_eq_15 = &r_nib_cnt[3:0];   // NibCnt == 15

    // Nibble >= MinFL before FCS.
    // Ethernet min frame is 64 bytes including FCS.
    // MAC must have at least 60 bytes before FCS.
    // 60 bytes = 120 nibbles, count value 119 means enough.
    assign o_nib_min_fl = r_nib_cnt >= (((MIN_FL - 16'd4) << 1) - 16'd1);

    // Excessive defer detection is always enabled.
    assign o_excessive_defer = r_nib_cnt[13:0] == EXCESSIVE_DEF_CNT;

    //============================================================
    // Byte counter
    //============================================================
    // Byte count increments after high nibble, or every 2 pad/FCS nibbles.
    wire w_byte_inc = (w_data_high & ~o_byte_max)
                    | (i_st_backoff & &r_nib_cnt[6:0])
                    | ((i_st_pad | i_st_fcs) & r_nib_cnt[0] & ~o_byte_max);

    wire w_byte_rst = i_start_backoff | (i_st_idle & i_tx_start_frm) | i_packet_finished_q;

    reg [15:0] r_byte_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_byte_cnt <= 16'd0;
        else if (w_byte_rst)
            r_byte_cnt <= 16'd0;
        else if (w_byte_inc)
            r_byte_cnt <= r_byte_cnt + 16'd1;
    end

    assign o_byte_cnt = r_byte_cnt;
    assign o_byte_max = (r_byte_cnt >= MAX_FL);

endmodule
