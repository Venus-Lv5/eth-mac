`timescale 1ns/1ps

// eth_rx_mac.v
// RX MAC module - Combines RX FSM, counters, address check, and CRC
// Based on ethmac eth_rxethmac.v
// Buffer-based version: removed DlyCrcEn, HugEn, configurable MaxFL
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
    input wire              i_fil_en,          // FIL_EN: Multicast hash enable
    input wire              i_pass_ctrl,       // Kept for old address-check compatibility

    // MAC address and hash table
    input wire [47:0]      i_mac_addr,        // This station MAC address
    input wire [31:0]      i_hash0,           // HASH_0 register (multicast)
    input wire [31:0]      i_hash1,           // HASH_1 register (multicast)

    // Control frame address OK (for PAUSE frames)
    input wire              i_ctrl_addr_ok,    // Control frame address matched

    // RX data output (to RX buffer controller)
    output wire [7:0]      o_rx_data,        // Assembled byte data
    output wire             o_rx_valid,       // Data valid strobe
    output wire             o_rx_start,        // Start of frame
    output wire             o_rx_end,          // End of frame

    // RX status (to RX buffer controller/registers)
    output wire             o_rx_abort,        // Frame aborted (bad address/CRC)
    output wire             o_crc_err,         // CRC error detected
    output wire             o_addr_miss,       // Address miss/debug status
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
    wire             w_ctrl_addr_ok;

    wire [31:0]     w_crc;
    wire             w_crc_err;

    wire             w_rx_valid_gen;
    wire             w_rx_start_gen;
    wire             w_rx_end_gen;
    wire             w_dribble_end;

    reg              r_crc_hash_good;
    reg [5:0]        r_crc_hash;

    wire             w_crc_enable;
    wire             w_crc_init;
    wire [3:0]       w_crc_data;
    wire [7:0]       w_assembled_byte;

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
    reg             r_pause_da_ok;

    localparam [47:0] PAUSE_DA = 48'h0180C2000001;

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
        .o_start_preamble   (),
        .o_start_sfd        (),
        .o_start_data       (),
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
        .o_byte_lt_7        (),
        .o_byte_max_frame   (w_byte_max_frame)
    );

    //============================================================
    // CRC Generation
    //============================================================
    // Enable CRC when in data state and not at max frame
    assign w_crc_enable = i_rx_dv & (|w_st_data) & ~w_byte_max_frame;
    // Khoi tao CRC tai nibble D cua SFD.
    assign w_crc_init = w_st_sfd & i_rx_dv & (i_rx_data == 4'hD);

    // Dao bit trong tung nibble de khop convention cua eth_crc.
    assign w_crc_data[0] = i_rx_data[3];
    assign w_crc_data[1] = i_rx_data[2];
    assign w_crc_data[2] = i_rx_data[1];
    assign w_crc_data[3] = i_rx_data[0];

    eth_crc u_crc (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_data     (w_crc_data),
        .i_enable   (w_crc_enable),
        .i_init     (w_crc_init),
        .o_crc      (w_crc),
        .o_crc_err  (w_crc_err)
    );

    //============================================================
    // CRC Hash for Multicast (captured after destination address)
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_crc_hash_good <= 1'b0;
        else
            r_crc_hash_good <= w_st_data[0] & w_byte_eq_6;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_crc_hash[5:0] <= 6'h0;
        else if (w_st_idle)
            r_crc_hash[5:0] <= 6'h0;
        else if (w_st_data[0] & w_byte_eq_6)
            r_crc_hash[5:0] <= w_crc[31:26];
    end

    //============================================================
    // Nibble-to-Byte Assembly
    //============================================================
    // MII is 4-bit interface, need to assemble 2 nibbles into 1 byte.
    // PHY gives low nibble first, then high nibble.
    assign w_assembled_byte = {i_rx_data[3:0], r_latched_byte[7:4]};

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
            r_delay_data <= w_st_data[1];
    end

    //============================================================
    // RxData Output Pipeline
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_data_d[7:0] <= 8'h0;
        end else begin
            if (w_rx_valid_gen)
                r_rx_data_d[7:0] <= w_assembled_byte;
            else if (~r_delay_data)
                r_rx_data_d[7:0] <= 8'h0;
        end
    end

    assign o_rx_data = r_rx_data_d;

    //============================================================
    // RxValid Generation
    //============================================================
    assign w_rx_valid_gen = w_st_data[1];

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
    assign w_rx_start_gen = w_st_data[1] & w_byte_eq_0;

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
            if (w_st_data[1] & ~(&w_assembled_byte) & w_byte_cnt < 16'd6)
                r_broadcast <= 1'b0;
            else if (w_st_data[1] & (&w_assembled_byte) & w_byte_eq_0)
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
            if (w_st_data[1] & w_byte_eq_0 & w_assembled_byte[0])
                r_multicast <= 1'b1;
            else if (o_rx_end | w_rx_abort_addr)
                r_multicast <= 1'b0;
        end
    end

    assign w_multicast = r_multicast;

    //============================================================
    // PAUSE control address detection
    //============================================================
    // PAUSE DA 01-80-C2-00-00-01 can be accepted for internal
    // pause handling even when normal multicast hash does not match.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_pause_da_ok <= 1'b0;
        else if (o_rx_end | w_rx_abort_addr | w_st_idle)
            r_pause_da_ok <= 1'b0;
        else if (w_st_data[1] & w_byte_eq_0)
            r_pause_da_ok <= (w_assembled_byte == PAUSE_DA[47:40]);
        else if (w_st_data[1] & w_byte_eq_1)
            r_pause_da_ok <= r_pause_da_ok &
                             (w_assembled_byte == PAUSE_DA[39:32]);
        else if (w_st_data[1] & w_byte_eq_2)
            r_pause_da_ok <= r_pause_da_ok &
                             (w_assembled_byte == PAUSE_DA[31:24]);
        else if (w_st_data[1] & w_byte_eq_3)
            r_pause_da_ok <= r_pause_da_ok &
                             (w_assembled_byte == PAUSE_DA[23:16]);
        else if (w_st_data[1] & w_byte_eq_4)
            r_pause_da_ok <= r_pause_da_ok &
                             (w_assembled_byte == PAUSE_DA[15:8]);
        else if (w_st_data[1] & w_byte_eq_5)
            r_pause_da_ok <= r_pause_da_ok &
                             (w_assembled_byte == PAUSE_DA[7:0]);
    end

    assign w_ctrl_addr_ok = i_ctrl_addr_ok | r_pause_da_ok;

    //============================================================
    // Address Checking
    //============================================================
    eth_rx_addr_check u_addr_check (
        .i_clk              (i_clk),
        .i_rst_n            (i_rst_n),
        .i_rx_data          (w_assembled_byte),
        .i_multicast        (w_multicast),
        .i_broadcast        (w_broadcast),
        .i_st_data          (w_st_data),
        .i_byte_eq_0        (w_byte_eq_0),
        .i_byte_eq_1        (w_byte_eq_1),
        .i_byte_eq_2        (w_byte_eq_2),
        .i_byte_eq_3        (w_byte_eq_3),
        .i_byte_eq_4        (w_byte_eq_4),
        .i_byte_eq_5        (w_byte_eq_5),
        .i_byte_eq_6        (w_byte_eq_6),
        .i_byte_eq_7        (w_byte_eq_7),
        .i_mac_addr         (i_mac_addr),
        .i_hash0            (i_hash0),
        .i_hash1            (i_hash1),
        .i_crc_hash         (r_crc_hash),
        .i_crc_hash_good    (r_crc_hash_good),
        .i_rx_end_frm       (o_rx_end),
        .i_pro              (i_pro),
        .i_bro              (i_bro),
        .i_fil_en           (i_fil_en),
        .i_pass_ctrl        (i_pass_ctrl),
        .i_ctrl_addr_ok     (w_ctrl_addr_ok),
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
