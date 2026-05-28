`timescale 1ns/1ps

// eth_rx_mac.v
// RX MAC module - Combines RX FSM, counters, address check, and CRC
// Based on ethmac eth_rxethmac.v
// Simplified per DESIGN_NOTES.md: removed DlyCrcEn, HugEn, configurable MaxFL
// REMOVED: MII management, per-register PAD/CRC config

module eth_rx_mac (
    // Global
    input wire              i_clk,
    input wire              i_rst_n,

    // MII interface (from PHY)
    input wire              i_rx_dv,          // RX data valid
    input wire [3:0]       i_rx_data,        // RX nibble data

    // Control signals
    input wire              i_rx_en,          // RX enable from MAC_CTRL
    input wire              i_transmitting,    // TX MAC transmitting (collision in HDX)
    input wire              i_pro,             // PRO: Promiscuous mode
    input wire              i_bro,             // BRO: Broadcast enable
    input wire              i_pass_ctrl,       // PASS_CTRL: Forward control frames

    // MAC address and hash table
    input wire [47:0]      i_mac_addr,        // This station MAC address
    input wire [31:0]      i_hash0,           // HASH_0 register (multicast)
    input wire [31:0]      i_hash1,           // HASH_1 register (multicast)

    // Control frame address OK (for PAUSE frames)
    input wire              i_ctrl_addr_ok,    // Control frame address matched

    // RX data output (to RX DMA/FIFO)
    output wire [7:0]      o_rx_data,        // Assembled byte data
    output wire             o_rx_valid,       // Data valid strobe
    output wire             o_rx_start,        // Start of frame
    output wire             o_rx_end,          // End of frame

    // RX status (to RX DMA)
    output wire             o_rx_abort,        // Frame aborted (bad address/CRC)
    output wire             o_crc_err,         // CRC error detected
    output wire             o_addr_miss,       // Address miss (for BD status)
    output wire             o_rx_ready         // RX ready for next frame
);

    //============================================================
    // Internal signals
    //============================================================
    wire [1:0]      w_st_data;
    wire             w_st_idle;
    wire             w_st_drop;
    wire             w_st_preamble;
    wire             w_st_sfd;

    wire [15:0]     w_byte_cnt;
    wire             w_byte_eq_0;
    wire             w_byte_eq_1;
    wire             w_byte_eq_2;
    wire             w_byte_eq_3;
    wire             w_byte_eq_4;
    wire             w_byte_eq_5;
    wire             w_byte_eq_6;
    wire             w_byte_eq_7;
    wire             w_byte_gt_2;
    wire             w_byte_max_frame;
    wire             w_ifg_eq_24;

    wire             w_rx_abort_fsm;
    wire             w_rx_abort_addr;
    wire             w_multicast;
    wire             w_broadcast;

    wire [31:0]     w_crc;
    wire             w_crc_err;

    wire             w_rx_valid_gen;
    wire             w_rx_start_gen;
    wire             w_rx_end_gen;
    wire             w_dribble_end;

    wire             w_crc_hash_good;
    wire [5:0]      w_crc_hash;

    wire             w_crc_enable;
    wire             w_crc_init;

    reg [7:0]       r_latched_byte;
    reg [7:0]       r_rx_data_d;
    reg             r_delay_data;
    reg             r_rx_valid_d;
    reg             r_rx_valid;
    reg             r_rx_start_d;
    reg             r_rx_start;
    reg             r_rx_end_d;
    reg             r_rx_end;
    reg             r_multicast;
    reg             r_broadcast;

    //============================================================
    // RX FSM Controller
    //============================================================
    eth_rx_controller u_rx_controller (
        .i_clk              (i_clk),
        .i_rst_n            (i_rst_n),
        .i_rx_dv            (i_rx_dv),
        .i_rx_data          (i_rx_data),
        .i_byte_eq_0        (w_byte_eq_0),
        .i_byte_max_frame   (w_byte_max_frame),
        .i_ifg_eq_24        (w_ifg_eq_24),
        .i_transmitting     (i_transmitting),
        .i_rx_en            (i_rx_en),
        .o_state_idle       (w_st_idle),
        .o_state_drop       (w_st_drop),
        .o_state_preamble   (w_st_preamble),
        .o_state_sfd        (w_st_sfd),
        .o_state_data       (w_st_data),
        .o_rx_abort         (w_rx_abort_fsm)
    );

    //============================================================
    // RX Counters
    //============================================================
    eth_rx_cnt u_rx_cnt (
        .i_clk              (i_clk),
        .i_rst_n            (i_rst_n),
        .i_st_idle          (w_st_idle),
        .i_st_preamble      (w_st_preamble),
        .i_st_sfd           (w_st_sfd),
        .i_st_data          (w_st_data),
        .i_st_drop          (w_st_drop),
        .i_rx_dv            (i_rx_dv),
        .i_rx_eq_d          (i_rx_data == 4'hD),
        .i_will_transmit    (i_transmitting),
        .o_ifg_cnt_eq24     (w_ifg_eq_24),
        .o_byte_cnt         (w_byte_cnt),
        .o_byte_eq_0        (w_byte_eq_0),
        .o_byte_eq_1        (w_byte_eq_1),
        .o_byte_eq_2        (w_byte_eq_2),
        .o_byte_eq_3        (w_byte_eq_3),
        .o_byte_eq_4        (w_byte_eq_4),
        .o_byte_eq_5        (w_byte_eq_5),
        .o_byte_eq_6        (w_byte_eq_6),
        .o_byte_eq_7        (w_byte_eq_7),
        .o_byte_gt_2        (w_byte_gt_2),
        .o_byte_max_frame   (w_byte_max_frame)
    );

    //============================================================
    // CRC Generation
    //============================================================
    // Enable CRC when in data state and not at max frame
    assign w_crc_enable = i_rx_dv & (|w_st_data) & ~w_byte_max_frame;
    // Initialize CRC when entering SFD
    assign w_crc_init = w_st_sfd & i_rx_dv;

    eth_crc u_crc (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_data     (i_rx_data),
        .i_enable   (w_crc_enable),
        .i_init     (w_crc_init),
        .o_crc      (w_crc),
        .o_crc_err  (w_crc_err)
    );

    //============================================================
    // CRC Hash for Multicast (captured after byte 6)
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            w_crc_hash_good <= 1'b0;
        else
            w_crc_hash_good <= w_st_data[0] & w_byte_eq_6;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            w_crc_hash[5:0] <= 6'h0;
        else if (w_st_idle)
            w_crc_hash[5:0] <= 6'h0;
        else if (w_st_data[0] & w_byte_eq_6)
            w_crc_hash[5:0] <= w_crc[31:26];
    end

    //============================================================
    // Nibble-to-Byte Assembly
    //============================================================
    // MII is 4-bit interface, need to assemble 2 nibbles into 1 byte
    // Latch MSB nibble first, then shift in LSB nibble
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_latched_byte[7:0] <= 8'h0;
        else
            r_latched_byte[7:0] <= {i_rx_data[3:0], r_latched_byte[7:4]};
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_delay_data <= 1'b0;
        else
            r_delay_data <= w_st_data[0];
    end

    //============================================================
    // RxData Output Pipeline
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_data_d[7:0] <= 8'h0;
        end else begin
            if (w_rx_valid_gen)
                r_rx_data_d[7:0] <= r_latched_byte[7:0] & {8{|w_st_data}};
            else if (~r_delay_data)
                r_rx_data_d[7:0] <= 8'h0;
        end
    end

    assign o_rx_data = r_rx_data_d;

    //============================================================
    // RxValid Generation
    //============================================================
    assign w_rx_valid_gen = w_st_data[0];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_valid_d <= 1'b0;
            r_rx_valid <= 1'b0;
        end else begin
            r_rx_valid_d <= w_rx_valid_gen;
            r_rx_valid <= r_rx_valid_d;
        end
    end

    assign o_rx_valid = r_rx_valid;

    //============================================================
    // RxStart Generation
    //============================================================
    assign w_rx_start_gen = w_st_data[0] & w_byte_eq_1;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_start_d <= 1'b0;
            r_rx_start <= 1'b0;
        end else begin
            r_rx_start_d <= w_rx_start_gen;
            r_rx_start <= r_rx_start_d;
        end
    end

    assign o_rx_start = r_rx_start;

    //============================================================
    // RxEnd Generation
    //============================================================
    // End frame when MRxDV goes low in Data state (after byte 2)
    // OR when max frame size reached
    assign w_rx_end_gen = w_st_data[0] & (~i_rx_dv & w_byte_gt_2);
    // Dribble: odd byte at end (MRxDV goes low when only half byte received)
    assign w_dribble_end = w_st_data[1] & ~i_rx_dv & w_byte_gt_2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_end_d <= 1'b0;
            r_rx_end <= 1'b0;
        end else begin
            r_rx_end_d <= w_rx_end_gen;
            r_rx_end <= r_rx_end_d | w_dribble_end;
        end
    end

    assign o_rx_end = r_rx_end;

    //============================================================
    // Broadcast Detection
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_broadcast <= 1'b0;
        else begin
            if (w_st_data[0] & ~(&r_latched_byte[7:0]) & w_byte_cnt < 16'd7)
                r_broadcast <= 1'b0;
            else if (w_st_data[0] & (&r_latched_byte[7:0]) & w_byte_eq_1)
                r_broadcast <= 1'b1;
            else if (o_rx_end | w_rx_abort_addr)
                r_broadcast <= 1'b0;
        end
    end

    assign w_broadcast = r_broadcast;

    //============================================================
    // Multicast Detection
    //============================================================
    // Multicast: bit 0 of first byte = 1 (excluding broadcast FF:FF:FF:FF:FF:FF)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_multicast <= 1'b0;
        else begin
            if (w_st_data[0] & w_byte_eq_1 & r_latched_byte[0])
                r_multicast <= 1'b1;
            else if (o_rx_end | w_rx_abort_addr)
                r_multicast <= 1'b0;
        end
    end

    assign w_multicast = r_multicast;

    //============================================================
    // Address Checking
    //============================================================
    eth_rx_addr_check u_addr_check (
        .i_clk              (i_clk),
        .i_rst_n            (i_rst_n),
        .i_rx_data          (r_latched_byte),
        .i_multicast        (w_multicast),
        .i_broadcast        (w_broadcast),
        .i_st_data          (w_st_data),
        .i_byte_eq_0        (w_byte_eq_0),
        .i_byte_eq_2        (w_byte_eq_2),
        .i_byte_eq_3        (w_byte_eq_3),
        .i_byte_eq_4        (w_byte_eq_4),
        .i_byte_eq_5        (w_byte_eq_5),
        .i_byte_eq_6        (w_byte_eq_6),
        .i_byte_eq_7        (w_byte_eq_7),
        .i_mac_addr         (i_mac_addr),
        .i_hash0            (i_hash0),
        .i_hash1            (i_hash1),
        .i_crc_hash         (w_crc_hash),
        .i_crc_hash_good    (w_crc_hash_good),
        .i_rx_end_frm       (o_rx_end),
        .i_pro              (i_pro),
        .i_bro              (i_bro),
        .i_pass_ctrl        (i_pass_ctrl),
        .i_ctrl_addr_ok     (i_ctrl_addr_ok),
        .o_rx_abort         (w_rx_abort_addr),
        .o_addr_miss        (o_addr_miss)
    );

    //============================================================
    // Combined RX Abort
    //============================================================
    assign o_rx_abort = w_rx_abort_fsm | w_rx_abort_addr;

    //============================================================
    // Status outputs
    //============================================================
    assign o_crc_err = w_crc_err;

    // RX ready when idle and not receiving
    assign o_rx_ready = w_st_idle;

endmodule
