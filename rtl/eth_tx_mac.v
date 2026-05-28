// eth_tx_mac.v
// Ethernet TX MAC (Simplified for 10/100)
// Based on ethmac eth_txethmac.v
// Reference: IEEE 802.3
//
// Differences from ethmac:
// - No MII Management (PHY pre-configured)
// - No configurable IPG timing (PHY handles)
// - No HugEn, DlyCrcEn, NoBckof, ExDfrEn
// - PAD/CRC from TX BD (per-packet)
// - Fixed: MinFL=64, MaxFL=1518, MaxRet=15, CollValid=63

`timescale 1ns/1ps

module eth_tx_mac (
    // Clock & Reset
    input  wire        i_clk,
    input  wire        i_rst_n,

    // TX Frame Control (from TX DMA)
    input  wire        i_tx_start,      // Start frame
    input  wire        i_tx_end,        // End frame
    input  wire        i_tx_underrun,  // FIFO empty
    input  wire [7:0]  i_tx_data,       // TX data byte

    // Per-packet config (from TX BD)
    input  wire        i_pad_en,        // Enable padding
    input  wire        i_crc_en,        // Enable CRC

    // Duplex mode (from MAC_CTRL register)
    input  wire        i_full_duplex,   // 1=FDX, 0=HDX

    // MII signals (synchronized)
    input  wire        i_carrier_sense, // Carrier detected
    input  wire        i_collision,     // Collision detected

    // TX output (to PHY)
    output wire  [3:0] o_mtx_d,         // TX nibble
    output wire        o_mtx_en,         // TX enable
    output wire        o_mtx_err,        // TX error

    // Status (to TX DMA / Registers)
    output wire        o_tx_done,        // Frame transmitted OK
    output wire        o_tx_retry,       // Frame needs retry
    output wire        o_tx_abort,       // Frame aborted
    output wire        o_tx_used_data,   // FIFO data consumed

    // Status for statistics
    output wire        o_defer_ind,      // Deferred due to carrier
    output wire        o_late_collision, // Late collision occurred
    output wire        o_max_collision,  // Max retry reached
    output wire        o_will_transmit    // Will transmit (for Rx)
);

    //============================================================
    // Constants (IEEE 802.3 fixed values)
    //============================================================
    localparam [15:0] LPARAM_MIN_FL     = 16'd64;   // Min frame length (bytes)
    localparam [15:0] LPARAM_MAX_FL     = 16'd1518; // Max frame length (bytes)
    localparam [5:0]  LPARAM_COLL_VALID = 6'd63;   // Collision window (64 bytes)
    localparam [3:0]  LPARAM_MAX_RET    = 4'd15;   // Max retry attempts

    //============================================================
    // Internal signals
    //============================================================

    // FSM state outputs
    wire        w_state_idle;
    wire        w_state_ipg;
    wire        w_state_preamble;
    wire  [1:0] w_state_data;
    wire        w_state_pad;
    wire        w_state_fcs;
    wire        w_state_jam;
    wire        w_state_jam_q;
    wire        w_state_backoff;
    wire        w_state_defer;

    // FSM control signals
    wire        w_start_ipg;
    wire        w_start_preamble;
    wire  [1:0] w_start_data;
    wire        w_start_fcs;
    wire        w_start_jam;
    wire        w_start_backoff;
    wire        w_start_defer;

    // Counters
    wire [15:0] w_nib_cnt;
    wire [15:0] w_byte_cnt;
    wire        w_nib_eq7;
    wire        w_nib_eq15;
    wire        w_nibble_min_fl;
    wire        w_max_frame;
    wire        w_excessive_defer;
    wire        w_state_sfd;
    wire        w_byte_max;

    // Collision handling
    wire        w_col_window;            // Inside collision window
    wire        w_under_run;            // FIFO underrun during data
    wire        w_too_big;              // Frame > MaxFL
    wire        w_retry_max;
    wire        w_late_collision;
    wire        w_max_collision_occured;
    wire        w_excessive_defer_occured;
    wire  [3:0] w_retry_cnt;

    // CRC
    wire [31:0] w_crc;
    wire        w_enable_crc;
    wire [3:0]  w_data_crc;
    wire        w_init_crc;

    // Random (backoff)
    wire        w_random_eq0;
    wire        w_random_eq_byte_cnt;

    // Internal control
    reg         r_col_window;
    reg         r_stop_excessive_defer;
    reg         r_status_latch;
    reg         r_tx_done;
    reg         r_tx_retry;
    reg         r_tx_abort;
    reg         r_tx_used_data;
    reg         r_will_transmit;
    reg         r_mtx_en;
    reg         r_mtx_err;
    reg   [3:0] r_mtx_d;
    reg   [3:0] r_mtx_d_d;
    reg         r_packet_finished;
    reg         r_packet_finished_q;

    // Additional control signals
    wire        w_start_tx_done;
    wire        w_start_tx_retry;
    wire        w_start_tx_abort;
    wire        w_packet_finished;

    //============================================================
    // Reset Collision (synchronizer)
    //============================================================
    // Collision signal should be reset when not transmitting
    assign w_reset_collision = ~(w_state_preamble | |w_state_data | w_state_pad | w_state_fcs);

    //============================================================
    // Excessive Defer Detection
    //============================================================
    // Defer > 24KB (24576 bits = 6144 nibbles)
    assign w_excessive_defer_occured = i_tx_start & w_state_defer & w_excessive_defer & ~r_stop_excessive_defer;

    // Stop excessive defer flag (set once, cleared when tx_start deasserted)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_stop_excessive_defer <= 1'b0;
        else if (!i_tx_start)
            r_stop_excessive_defer <= 1'b0;
        else if (w_excessive_defer_occured)
            r_stop_excessive_defer <= 1'b1;
    end

    //============================================================
    // Collision Window
    //============================================================
    // Collision window = 512 bit-times = 64 bytes (CollValid=63)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_col_window <= 1'b1;
        else if (!i_collision & (w_byte_cnt[5:0] == LPARAM_COLL_VALID) &
             (w_state_data[1] | w_state_pad & w_nib_cnt[0] | w_state_fcs & w_nib_cnt[0]))
            r_col_window <= 1'b0;
        else if (w_state_idle | w_state_ipg)
            r_col_window <= 1'b1;
    end

    assign w_col_window = r_col_window;

    //============================================================
    // Status Latch (for avoiding status overwrite)
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_status_latch <= 1'b0;
        else if (!i_tx_start)
            r_status_latch <= 1'b0;
        else if (w_excessive_defer_occured | w_state_idle)
            r_status_latch <= 1'b1;
    end

    //============================================================
    // Retry Counter
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            w_retry_cnt <= 4'h0;
        else if (w_excessive_defer_occured | w_under_run | w_too_big |
                 w_start_tx_done | i_tx_underrun |
                 (w_state_jam & w_nib_eq7 & (~w_col_window | w_retry_max)))
            w_retry_cnt <= 4'h0;
        else if ((w_state_jam & w_nib_eq7 & w_col_window & (w_random_eq0)) |
                 (w_state_backoff & w_random_eq_byte_cnt))
            w_retry_cnt <= w_retry_cnt + 4'd1;
    end

    assign w_retry_max = (w_retry_cnt == LPARAM_MAX_RET);

    //============================================================
    // TX Status Signals
    //============================================================

    // Start TX Done: FCS complete OR Data done (no CRC)
    assign w_start_tx_done = ~i_collision &
        (w_state_fcs & w_nib_eq7 |
         w_state_data[1] & i_tx_end & (~i_pad_en | i_pad_en & w_nibble_min_fl) & ~i_crc_en);

    // Underrun: Data state + FIFO empty
    assign w_under_run = w_state_data[0] & i_tx_underrun & ~i_collision;

    // Too big: Frame exceeds MaxFL
    assign w_too_big = ~i_collision & w_max_frame &
        (w_state_data[0] & ~i_tx_underrun | w_state_fcs);

    // Start TX Retry: Jam in collision window, not max retry, not underrun
    assign w_start_tx_retry = w_start_jam & w_col_window & ~w_retry_max & ~w_under_run;

    // Late Collision: Jam outside collision window, not underrun
    assign w_late_collision = w_start_jam & ~w_col_window & ~w_under_run;

    // Max Collision: Jam + max retry reached
    assign w_max_collision_occured = w_start_jam & w_col_window & w_retry_max;

    // Start TX Abort
    assign w_start_tx_abort = w_too_big | w_under_run | w_excessive_defer_occured |
                              w_late_collision | w_max_collision_occured;

    // SFD indicator
    assign w_state_sfd = w_state_preamble & w_nib_eq15;

    //============================================================
    // Status Output Registers
    //============================================================

    // TX Used Data
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_used_data <= 1'b0;
        else
            r_tx_used_data <= |w_start_data;
    end

    // TX Done
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_done <= 1'b0;
        else if (i_tx_start & ~r_status_latch)
            r_tx_done <= 1'b0;
        else if (w_start_tx_done)
            r_tx_done <= 1'b1;
    end

    // TX Retry
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_retry <= 1'b0;
        else if (i_tx_start & ~r_status_latch)
            r_tx_retry <= 1'b0;
        else if (w_start_tx_retry)
            r_tx_retry <= 1'b1;
    end

    // TX Abort
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_abort <= 1'b0;
        else if (i_tx_start & ~r_status_latch & ~w_excessive_defer_occured)
            r_tx_abort <= 1'b0;
        else if (w_start_tx_abort)
            r_tx_abort <= 1'b1;
    end

    // Will Transmit (for Rx MAC to detect collision in FDX)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_will_transmit <= 1'b0;
        else
            r_will_transmit <= w_start_preamble | w_state_preamble | |w_state_data |
                               w_state_pad | w_state_fcs | w_state_jam;
    end

    // Packet Finished (combinational)
    assign w_packet_finished = w_start_tx_done | w_too_big | w_under_run |
                                w_late_collision | w_max_collision_occured |
                                w_excessive_defer_occured;

    // Packet Finished Register
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_packet_finished <= 1'b0;
            r_packet_finished_q <= 1'b0;
        end else begin
            r_packet_finished <= w_packet_finished;
            r_packet_finished_q <= r_packet_finished;
        end
    end

    //============================================================
    // TX Enable & Error
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mtx_en <= 1'b0;
        else
            r_mtx_en <= w_state_preamble | |w_state_data | w_state_pad |
                        w_state_fcs | w_state_jam;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mtx_err <= 1'b0;
        else
            r_mtx_err <= w_too_big | w_under_run;
    end

    //============================================================
    // TX Data MUX
    //============================================================
    // Selects nibble to transmit based on current state
    always @(*) begin
        if (w_state_data[0])
            r_mtx_d_d = i_tx_data[3:0];                      // Lower nibble
        else if (w_state_data[1])
            r_mtx_d_d = i_tx_data[7:4];                     // Higher nibble
        else if (w_state_fcs)
            r_mtx_d_d = ~w_crc[31:28];                      // CRC (inverted per IEEE)
        else if (w_state_jam)
            r_mtx_d_d = 4'h9;                               // Jam pattern
        else if (w_state_preamble)
            r_mtx_d_d = w_nib_eq15 ? 4'hD : 4'h5;           // SFD or Preamble
        else
            r_mtx_d_d = 4'h0;
    end

    // TX Data Register
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mtx_d <= 4'h0;
        else
            r_mtx_d <= r_mtx_d_d;
    end

    //============================================================
    // CRC Logic
    //============================================================
    assign w_enable_crc = ~w_state_fcs;  // Enable during data, disable during FCS

    // Data nibble being transmitted (LSB first for CRC)
    assign w_data_crc[0] = w_state_data[0] ? i_tx_data[3] : w_state_data[1] ? i_tx_data[7] : 1'b0;
    assign w_data_crc[1] = w_state_data[0] ? i_tx_data[2] : w_state_data[1] ? i_tx_data[6] : 1'b0;
    assign w_data_crc[2] = w_state_data[0] ? i_tx_data[1] : w_state_data[1] ? i_tx_data[5] : 1'b0;
    assign w_data_crc[3] = w_state_data[0] ? i_tx_data[0] : w_state_data[1] ? i_tx_data[4] : 1'b0;

    // Initialize CRC at start of frame
    assign w_init_crc = w_state_idle | w_state_preamble;

    //============================================================
    // Sub-modules instantiation
    //============================================================

    // TX Counters (nibble/byte count, frame length check)
    eth_tx_cnt #(
        .MIN_FL           (LPARAM_MIN_FL),
        .MAX_FL           (LPARAM_MAX_FL)
    ) u_tx_cnt (
        .i_clk              (i_clk),
        .i_rst_n            (i_rst_n),
        .i_st_preamble      (w_state_preamble),
        .i_st_ipg           (w_state_ipg),
        .i_st_data          (w_state_data),
        .i_st_pad           (w_state_pad),
        .i_st_fcs           (w_state_fcs),
        .i_st_jam           (w_state_jam),
        .i_st_backoff       (w_state_backoff),
        .i_st_defer         (w_state_defer),
        .i_st_idle          (w_state_idle),
        .i_start_defer      (w_start_defer),
        .i_start_ipg        (w_start_ipg),
        .i_start_fcs        (w_start_fcs),
        .i_start_jam        (w_start_jam),
        .i_start_backoff    (w_start_backoff),
        .i_tx_start_frm     (i_tx_start),
        .i_packet_finished_q(r_packet_finished_q),
        .o_nib_cnt          (w_nib_cnt),
        .o_byte_cnt         (w_byte_cnt),
        .o_nib_eq_7         (w_nib_eq7),
        .o_nib_eq_15        (w_nib_eq15),
        .o_nib_min_fl       (w_nibble_min_fl),
        .o_byte_max         (w_max_frame),
        .o_excessive_defer  (w_excessive_defer)
    );

    // TX State Machine (FSM)
    eth_txstatem u_tx_fsm (
        .i_clk               (i_clk),
        .i_rst_n             (i_rst_n),
        .i_excessive_defer   (w_excessive_defer),
        .i_carrier_sense     (i_carrier_sense),
        .i_full_duplex       (i_full_duplex),
        .i_tx_start          (i_tx_start),
        .i_tx_end            (i_tx_end),
        .i_tx_underrun       (i_tx_underrun),
        .i_tx_done           (w_start_tx_done),
        .i_collision         (i_collision),
        .i_underrun          (w_under_run),
        .i_col_window        (w_col_window),
        .i_retry_max         (w_retry_max),
        .i_random_eq0        (w_random_eq0),
        .i_random_eq_byte    (w_random_eq_byte_cnt),
        .i_pad_en            (i_pad_en),
        .i_crc_en            (i_crc_en),
        .i_nib_cnt           (w_nib_cnt[6:0]),
        .i_nib_eq7           (w_nib_eq7),
        .i_nib_eq15          (w_nib_eq15),
        .i_nib_min_fl        (w_nibble_min_fl),
        .i_max_frame         (w_max_frame),
        .i_too_big           (w_too_big),
        .o_state_idle        (w_state_idle),
        .o_state_ipg         (w_state_ipg),
        .o_state_preamble    (w_state_preamble),
        .o_state_data        (w_state_data),
        .o_state_pad         (w_state_pad),
        .o_state_fcs         (w_state_fcs),
        .o_state_jam         (w_state_jam),
        .o_state_jam_q       (w_state_jam_q),
        .o_state_backoff     (w_state_backoff),
        .o_state_defer       (w_state_defer),
        .o_start_ipg         (w_start_ipg),
        .o_start_preamble    (w_start_preamble),
        .o_start_data        (w_start_data),
        .o_start_fcs         (w_start_fcs),
        .o_start_jam         (w_start_jam),
        .o_start_backoff     (w_start_backoff),
        .o_start_defer       (w_start_defer),
        .o_defer_ind         (o_defer_ind)
    );

    // CRC Generator
    eth_crc u_crc (
        .i_clk     (i_clk),
        .i_rst_n   (i_rst_n),
        .i_data    (w_data_crc),
        .i_enable  (w_enable_crc),
        .i_init    (w_init_crc),
        .o_crc     (w_crc),
        .o_crc_err ()
    );

    // Random Number Generator (for backoff)
    eth_backoff_random #(
        .SEED (32'hDEADBEEF)
    ) u_backoff (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_state_jam      (w_state_jam),
        .i_state_jam_q    (w_state_jam_q),
        .i_retry_cnt      (w_retry_cnt),
        .i_nib_cnt        (w_nib_cnt),
        .i_byte_cnt        (w_byte_cnt[9:0]),
        .o_random_eq_0    (w_random_eq0),
        .o_random_eq_byte (w_random_eq_byte_cnt)
    );

    //============================================================
    // Output assignments
    //============================================================
    assign o_mtx_d          = r_mtx_d;
    assign o_mtx_en         = r_mtx_en;
    assign o_mtx_err       = r_mtx_err;
    assign o_tx_done        = r_tx_done;
    assign o_tx_retry       = r_tx_retry;
    assign o_tx_abort       = r_tx_abort;
    assign o_tx_used_data   = r_tx_used_data;
    assign o_will_transmit  = r_will_transmit;
    assign o_late_collision = w_late_collision;
    assign o_max_collision  = w_max_collision_occured;

endmodule
