// eth_backoff_random.v
// LFSR-based random number generator for IEEE 802.3 CSMA/CD backoff
// Backoff delay = slot_time × random(0, 2^k-1), where k = min(retry_cnt, 10)

module eth_backoff_random (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_state_jam,      // Jam state active
    input  wire        i_state_jam_q,    // Jam state delayed
    input  wire [3:0]  i_retry_cnt,      // Collision retry counter
    input  wire [15:0] i_nib_cnt,       // Nibble count from MAC
    input  wire [9:0]  i_byte_cnt,      // Byte count from MAC
    output wire        o_random_eq_0,    // Random = 0 (go to defer)
    output wire        o_random_eq_byte // ByteCnt reached random value
);

    // LFSR state register (10-bit)
    reg  [9:0] r_lfsr;

    // LFSR feedback: x[2] XOR x[9] (primitive polynomial)
    wire w_feedback = ~(r_lfsr[2] ^ r_lfsr[9]);

    // Random output masked by retry count
    wire [9:0] w_random;
    assign w_random[0] = r_lfsr[0];
    assign w_random[1] = (i_retry_cnt > 4'd1) ? r_lfsr[1] : 1'b0;
    assign w_random[2] = (i_retry_cnt > 4'd2) ? r_lfsr[2] : 1'b0;
    assign w_random[3] = (i_retry_cnt > 4'd3) ? r_lfsr[3] : 1'b0;
    assign w_random[4] = (i_retry_cnt > 4'd4) ? r_lfsr[4] : 1'b0;
    assign w_random[5] = (i_retry_cnt > 4'd5) ? r_lfsr[5] : 1'b0;
    assign w_random[6] = (i_retry_cnt > 4'd6) ? r_lfsr[6] : 1'b0;
    assign w_random[7] = (i_retry_cnt > 4'd7) ? r_lfsr[7] : 1'b0;
    assign w_random[8] = (i_retry_cnt > 4'd8) ? r_lfsr[8] : 1'b0;
    assign w_random[9] = (i_retry_cnt > 4'd9) ? r_lfsr[9] : 1'b0;

    // Latched random value during jam state
    reg [9:0] r_random_latched;

    // LFSR state update
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_lfsr <= 10'h000;
        else
            r_lfsr <= {r_lfsr[8:0], w_feedback};
    end

    // Latch random value when jam starts
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_random_latched <= 10'h000;
        else if (i_state_jam & i_state_jam_q)
            r_random_latched <= w_random;
    end

    // Random == 0: IEEE 802.3 requires defer, not backoff
    assign o_random_eq_0 = (r_random_latched == 10'h0);

    // Byte count reached random value: backoff delay complete
    assign o_random_eq_byte = (i_byte_cnt[9:0] == r_random_latched) & (&i_nib_cnt[6:0]);

endmodule
