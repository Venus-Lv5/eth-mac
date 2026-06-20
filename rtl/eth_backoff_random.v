`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Ethernet CSMA/CD backoff random generator
//
// Chuc nang:
// - Tao random 10 bit bang LFSR.
// - Cat so bit random theo retry count.
// - Chot random khi MAC vua vao JAM.
// - Bao random = 0 hoac backoff counter da dem toi random da chot.
//------------------------------------------------------------------------------
module eth_backoff_random #(
    parameter [31:0] SEED = 32'h000001D3
) (
    input  wire        i_clk,
    input  wire        i_rst_n,

    input  wire        i_state_jam,
    input  wire        i_state_jam_q,
    input  wire [3:0]  i_retry_cnt,
    input  wire [15:0] i_nib_cnt,
    input  wire [9:0]  i_byte_cnt,

    output wire        o_random_eq_0,
    output wire        o_random_eq_byte
);

    reg  [9:0] r_lfsr;
    reg  [9:0] r_random_latched;

    wire       w_jam_enter;
    wire       w_feedback;
    wire [9:0] w_random_masked;
    wire [10:0] w_slot_count_next;

    // Canh vao JAM. FSM tao i_state_jam_q la ban tre 1 chu ky cua JAM.
    assign w_jam_enter = i_state_jam & ~i_state_jam_q;

    // LFSR 10 bit. Dung feedback invert de tranh ket all-zero.
    assign w_feedback = ~(r_lfsr[2] ^ r_lfsr[9]);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_lfsr <= SEED[9:0];
        else
            r_lfsr <= {r_lfsr[8:0], w_feedback};
    end

    // Binary exponential backoff:
    // Lan retry dau tien dung 1 bit random: 0..1.
    // Moi lan retry sau mo them 1 bit, toi da 10 bit.
    assign w_random_masked[0] = r_lfsr[0];
    assign w_random_masked[1] = (i_retry_cnt >= 4'd1) ? r_lfsr[1] : 1'b0;
    assign w_random_masked[2] = (i_retry_cnt >= 4'd2) ? r_lfsr[2] : 1'b0;
    assign w_random_masked[3] = (i_retry_cnt >= 4'd3) ? r_lfsr[3] : 1'b0;
    assign w_random_masked[4] = (i_retry_cnt >= 4'd4) ? r_lfsr[4] : 1'b0;
    assign w_random_masked[5] = (i_retry_cnt >= 4'd5) ? r_lfsr[5] : 1'b0;
    assign w_random_masked[6] = (i_retry_cnt >= 4'd6) ? r_lfsr[6] : 1'b0;
    assign w_random_masked[7] = (i_retry_cnt >= 4'd7) ? r_lfsr[7] : 1'b0;
    assign w_random_masked[8] = (i_retry_cnt >= 4'd8) ? r_lfsr[8] : 1'b0;
    assign w_random_masked[9] = (i_retry_cnt >= 4'd9) ? r_lfsr[9] : 1'b0;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_random_latched <= 10'd0;
        else if (w_jam_enter)
            r_random_latched <= w_random_masked;
    end

    assign o_random_eq_0 = (r_random_latched == 10'd0);

    // eth_tx_cnt tang i_byte_cnt moi 128 nibble trong BACKOFF.
    // Vi vay i_byte_cnt o day la so slot-time da dem, khong phai byte frame.
    // Tai cuoi slot hien tai, slot_count_next moi la so slot vua hoan thanh.
    assign w_slot_count_next = {1'b0, i_byte_cnt} + 11'd1;
    assign o_random_eq_byte = (r_random_latched != 10'd0) &
                              (w_slot_count_next == {1'b0, r_random_latched}) &
                              (&i_nib_cnt[6:0]);

endmodule
