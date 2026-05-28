`timescale 1ns / 1ps

// eth_rx_cnt.v
// RX counters for IEEE 802.3 CSMA/CD reception
// Based on ethmac eth_rxcounters.v
// REMOVED per DESIGN_NOTES.md: DlyCrcEn, HugEn, configurable MaxFL, r_IFG

module eth_rx_cnt (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // State signals from RX FSM
    input  wire        i_st_idle,
    input  wire        i_st_preamble,
    input  wire        i_st_sfd,
    input  wire [1:0]  i_st_data,
    input  wire        i_st_drop,

    // Control signals
    input  wire        i_rx_dv,
    input  wire        i_rx_eq_d,
    input  wire        i_will_transmit,

    // Outputs
    output wire        o_ifg_cnt_eq24,   // IFG >= 24 clocks (9600ns)
    output wire [15:0] o_byte_cnt,       // Current byte count
    output wire        o_byte_eq_0,
    output wire        o_byte_eq_1,
    output wire        o_byte_eq_2,
    output wire        o_byte_eq_3,
    output wire        o_byte_eq_4,
    output wire        o_byte_eq_5,
    output wire        o_byte_eq_6,
    output wire        o_byte_eq_7,
    output wire        o_byte_gt_2,       // ByteCnt > 2
    output wire        o_byte_lt_7,       // ByteCnt < 7
    output wire        o_byte_max_frame  // ByteCnt == MAX_FL
);

    // Fixed parameter (per DESIGN_NOTES.md)
    // IEEE 802.3: Maximum frame size = 1518 bytes (excluding preamble/SFD)
    localparam [15:0] MAX_FL = 16'd1518;

    //============================================================
    // Byte Counter
    // Counts bytes received in current frame (after SFD)
    // Note: Byte counting starts from preamble/SFD, increments on odd nibbles
    //============================================================
    wire w_byte_rst = i_rx_dv & (i_st_idle & i_rx_eq_d | i_st_data[0] & o_byte_max_frame);
    wire w_byte_inc = ~w_byte_rst & i_rx_dv &
                      (i_st_idle & ~i_will_transmit |
                       i_st_preamble |              // Count during preamble
                       i_st_sfd |                  // Count during SFD
                       i_st_data[1] & ~o_byte_max_frame);

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

    // Byte counter flags
    assign o_byte_eq_0    = r_byte_cnt == 16'd0;
    assign o_byte_eq_1    = r_byte_cnt == 16'd1;
    assign o_byte_eq_2    = r_byte_cnt == 16'd2;
    assign o_byte_eq_3    = r_byte_cnt == 16'd3;
    assign o_byte_eq_4    = r_byte_cnt == 16'd4;
    assign o_byte_eq_5    = r_byte_cnt == 16'd5;
    assign o_byte_eq_6    = r_byte_cnt == 16'd6;
    assign o_byte_eq_7    = r_byte_cnt == 16'd7;
    assign o_byte_gt_2    = r_byte_cnt > 16'd2;
    assign o_byte_lt_7    = r_byte_cnt < 16'd7;
    assign o_byte_max_frame = r_byte_cnt == MAX_FL;

    //============================================================
    // IFG (Inter-Frame Gap) Counter
    // Counts 96 bit-times between frames
    // IEEE 802.3: minimum IFG = 96 bits = 24 nibbles/clocks at MII
    //============================================================
    wire w_ifg_rst = (i_st_idle & i_rx_dv & i_rx_eq_d) | i_st_drop;
    wire w_ifg_inc = ~w_ifg_rst & (i_st_drop | i_st_idle) & ~o_ifg_cnt_eq24;

    reg [4:0] r_ifg_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_ifg_cnt <= 5'd0;
        else if (w_ifg_rst)
            r_ifg_cnt <= 5'd0;
        else if (w_ifg_inc)
            r_ifg_cnt <= r_ifg_cnt + 5'd1;
    end

    // IFG >= 24 clocks (96 bit-times at MII 4-bit interface)
    assign o_ifg_cnt_eq24 = r_ifg_cnt == 5'd24;

endmodule
