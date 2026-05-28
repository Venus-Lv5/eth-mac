`timescale 1ns / 1ps

// eth_rx_addr_check.v
// RX address checking for IEEE 802.3 frame filtering
// Based on ethmac eth_rxaddrcheck.v
// Checks destination address: Unicast, Broadcast, Multicast, Control Frame

module eth_rx_addr_check (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // RX data and FSM state
    input  wire [7:0]  i_rx_data,
    input  wire        i_multicast,         // Bit 0 of first byte = 1
    input  wire        i_broadcast,         // First byte = 0xFF
    input  wire [1:0]  i_st_data,          // RX FSM state

    // Byte count flags (from eth_rx_cnt)
    input  wire        i_byte_eq_0,
    input  wire        i_byte_eq_2,
    input  wire        i_byte_eq_3,
    input  wire        i_byte_eq_4,
    input  wire        i_byte_eq_5,
    input  wire        i_byte_eq_6,
    input  wire        i_byte_eq_7,

    // MAC address
    input  wire [47:0] i_mac_addr,         // This station MAC address

    // Hash table for multicast
    input  wire [31:0] i_hash0,            // HASH_0 register
    input  wire [31:0] i_hash1,            // HASH_1 register

    // CRC hash for multicast
    input  wire [5:0]  i_crc_hash,         // CRC hash bits [31:26]
    input  wire        i_crc_hash_good,     // Hash valid (after byte 6)

    // Control signals
    input  wire        i_rx_end_frm,       // End of frame
    input  wire        i_pro,               // PRO bit - Promiscuous mode
    input  wire        i_bro,               // BRO bit - Broadcast enable
    input  wire        i_pass_ctrl,          // PASS_CTRL bit - Forward control frame
    input  wire        i_ctrl_addr_ok,      // Control frame address OK (PAUSE frame)

    // Outputs
    output wire        o_rx_abort,          // Abort this frame
    output wire        o_addr_miss           // Address miss (for RX BD)
);

    //============================================================
    // Internal signals
    //============================================================
    wire        w_rx_check_en;              // Address checking enabled
    wire        w_broadcast_ok;             // Broadcast allowed
    wire        w_rx_addr_invalid;          // Address not match
    wire        w_hash_bit;                 // Hash table lookup result
    wire [31:0] w_int_hash;                // Selected hash register
    wire [7:0]  w_byte_hash;               // Hash byte selection

    reg         r_unicast_ok;              // Unicast address match
    reg         r_multicast_ok;            // Multicast address match
    reg         r_rx_abort;                // Frame abort
    reg         r_addr_miss;               // Address miss status

    //============================================================
    // Address checking enable
    // Enable when RX FSM is in Data state
    //============================================================
    assign w_rx_check_en = |i_st_data;

    //============================================================
    // Broadcast detection
    // BRO=0: allow broadcast, BRO=1: reject broadcast
    //============================================================
    assign w_broadcast_ok = i_broadcast & ~i_bro;

    //============================================================
    // RxAbort logic
    // Abort when address doesn't match and not in promiscuous mode
    // Reported at end of address cycle, clears after one cycle
    //============================================================
    assign w_rx_addr_invalid = ~(r_unicast_ok | w_broadcast_ok | 
                                 r_multicast_ok | i_pro);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_abort <= 1'b0;
        else if (w_rx_addr_invalid & i_byte_eq_7 & w_rx_check_en)
            r_rx_abort <= 1'b1;
        else
            r_rx_abort <= 1'b0;
    end

    assign o_rx_abort = r_rx_abort;

    //============================================================
    // AddressMiss status
    // Written to RX BD to indicate frame received due to promiscuous
    // or control frame address match
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_addr_miss <= 1'b0;
        else if (i_byte_eq_0)
            r_addr_miss <= 1'b0;
        else if (i_byte_eq_7 & w_rx_check_en)
            r_addr_miss <= ~(r_unicast_ok | w_broadcast_ok | r_multicast_ok |
                           (i_pass_ctrl & i_ctrl_addr_ok));
    end

    assign o_addr_miss = r_addr_miss;

    //============================================================
    // Unicast address detection
    // Compare 6 bytes of destination address with MAC address
    // Start at ByteCntEq2 due to delay from RxData
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_unicast_ok <= 1'b0;
        else if (i_rx_end_frm | r_rx_abort)
            r_unicast_ok <= 1'b0;
        else if (w_rx_check_en & i_byte_eq_2)
            r_unicast_ok <= i_rx_data == i_mac_addr[47:40];
        else if (w_rx_check_en & i_byte_eq_3)
            r_unicast_ok <= (i_rx_data == i_mac_addr[39:32]) & r_unicast_ok;
        else if (w_rx_check_en & i_byte_eq_4)
            r_unicast_ok <= (i_rx_data == i_mac_addr[31:24]) & r_unicast_ok;
        else if (w_rx_check_en & i_byte_eq_5)
            r_unicast_ok <= (i_rx_data == i_mac_addr[23:16]) & r_unicast_ok;
        else if (w_rx_check_en & i_byte_eq_6)
            r_unicast_ok <= (i_rx_data == i_mac_addr[15:8]) & r_unicast_ok;
        else if (w_rx_check_en & i_byte_eq_7)
            r_unicast_ok <= (i_rx_data == i_mac_addr[7:0]) & r_unicast_ok;
    end

    //============================================================
    // Multicast hash table lookup
    //============================================================

    // Select HASH0 or HASH1 based on bit 5 of CRC hash
    assign w_int_hash = i_crc_hash[5] ? i_hash1 : i_hash0;

    // Select byte from hash register
    always @(i_crc_hash or w_int_hash) begin
        case (i_crc_hash[4:3])
            2'b00: w_byte_hash = w_int_hash[7:0];
            2'b01: w_byte_hash = w_int_hash[15:8];
            2'b10: w_byte_hash = w_int_hash[23:16];
            2'b11: w_byte_hash = w_int_hash[31:24];
        endcase
    end

    // Select bit from byte
    assign w_hash_bit = w_byte_hash[i_crc_hash[2:0]];

    // MulticastOK register
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_multicast_ok <= 1'b0;
        else if (i_rx_end_frm | r_rx_abort)
            r_multicast_ok <= 1'b0;
        else if (i_crc_hash_good & i_multicast)
            r_multicast_ok <= w_hash_bit;
    end

endmodule
