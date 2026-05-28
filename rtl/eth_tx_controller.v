// eth_txstatem.v
// Ethernet TX State Machine
// Simplified version for 10/100 MAC (no MII management)
// Reference: IEEE 802.3

`timescale 1ns/1ps

module eth_txstatem (
    // Global
    input wire              i_clk,
    input wire              i_rst_n,

    // Status
    input wire              i_excessive_defer,  // Defer > 24KB
    input wire              i_carrier_sense,    // Medium busy
    input wire              i_full_duplex,       // 1=FDX, 0=HDX

    // Control
    input wire              i_tx_start,          // Start frame
    input wire              i_tx_end,            // End frame
    input wire              i_tx_underrun,       // FIFO empty
    input wire              i_tx_done,            // Transmission complete

    // Collision (HDX only)
    input wire              i_collision,         // Collision detected
    input wire              i_underrun,          // FIFO underrun
    input wire              i_col_window,        // Inside collision window
    input wire              i_retry_max,         // Max retry reached
    input wire              i_random_eq0,        // Random = 0
    input wire              i_random_eq_byte,    // Random = byte count

    // Frame config (from BD)
    input wire              i_pad_en,            // Enable padding
    input wire              i_crc_en,            // Enable CRC

    // Counters
    input wire  [6:0]       i_nib_cnt,          // Nibble count
    input wire              i_nib_eq7,           // NibCnt == 7
    input wire              i_nib_eq15,          // NibCnt == 15
    input wire              i_nib_min_fl,        // >= MinFrame (64 bytes)
    input wire              i_max_frame,         // >= MaxFrame (1518 bytes)
    input wire              i_too_big,           // Frame > 1518

    // State outputs
    output reg              o_state_idle,
    output reg              o_state_ipg,
    output reg              o_state_preamble,
    output reg  [1:0]      o_state_data,
    output reg              o_state_pad,
    output reg              o_state_fcs,
    output reg              o_state_jam,
    output reg              o_state_jam_q,
    output reg              o_state_backoff,
    output reg              o_state_defer,

    // Next-state flags
    output wire             o_start_ipg,
    output wire             o_start_preamble,
    output wire  [1:0]      o_start_data,
    output wire             o_start_fcs,
    output wire             o_start_jam,
    output wire             o_start_backoff,
    output wire             o_start_defer,
    output wire             o_defer_ind          // Deferred due to carrier
);

    // FSM state encoding
    localparam [3:0]
        ST_DEFER     = 4'd0,
        ST_IPG       = 4'd1,
        ST_IDLE      = 4'd2,
        ST_PREAMBLE  = 4'd3,
        ST_DATA      = 4'd4,
        ST_PAD       = 4'd5,
        ST_FCS       = 4'd6,
        ST_JAM       = 4'd7,
        ST_BACKOFF   = 4'd8;

    reg [3:0] r_state;
    reg [3:0] r_next;

    // Internal signals (not output)
    wire w_start_idle = (r_state == ST_IPG) & (i_nib_cnt >= 7'd24);
    wire w_start_pad = ~i_collision & (r_state == ST_DATA) & i_tx_end & i_pad_en & ~i_nib_min_fl;

    //============================================================
    // Next-state logic
    //============================================================

    // IPG: wait for 96 bit-times (24 nibbles) after defer
    assign o_start_ipg = (r_state == ST_DEFER) & ~i_excessive_defer & ~i_carrier_sense;

    // Preamble: start when idle + tx_start + no carrier
    assign o_start_preamble = (r_state == ST_IDLE) & i_tx_start & ~i_carrier_sense;

    // Data[0]: from preamble (after 15 nib) or continuing data
    assign o_start_data[0] = ~i_collision & (
        ((r_state == ST_PREAMBLE) & i_nib_eq15) |
        ((r_state == ST_DATA) & ~i_tx_end)
    );

    // Data[1]: from data[0] if more data to send
    assign o_start_data[1] = ~i_collision & (r_state == ST_DATA) & ~i_tx_underrun & ~i_max_frame;

    // PAD: frame too short (<64 bytes) and padding enabled
    // Note: internal only, used for state transition to FCS

    // FCS: end of data (+ optional pad), CRC enabled
    assign o_start_fcs = ~i_collision & (
        ((r_state == ST_DATA) & i_tx_end & (~i_pad_en | i_nib_min_fl) & i_crc_en) |
        ((r_state == ST_PAD) & i_nib_min_fl & i_crc_en)
    );

    // Jam: collision during preamble/data/pad/fcs
    assign o_start_jam = (i_collision | i_underrun) & (
        ((r_state == ST_PREAMBLE) & i_nib_eq15) |
        (|o_state_data) |
        (r_state == ST_PAD) |
        (r_state == ST_FCS)
    );

    // Backoff: after jam, in collision window, not max retry
    assign o_start_backoff = (r_state == ST_JAM) & ~i_random_eq0 & i_col_window &
                             ~i_retry_max & i_nib_eq7;

    // Defer: various conditions
    assign o_start_defer = (
        ((r_state == ST_IPG) & i_carrier_sense) |                  // Carrier detected during IPG
        ((r_state == ST_IDLE) & i_carrier_sense) |                // Carrier detected while idle
        ((r_state == ST_JAM) & i_nib_eq7 & (i_random_eq0 | ~i_col_window | i_retry_max)) | // Jam complete, no backoff
        ((r_state == ST_BACKOFF) & (i_tx_underrun | i_random_eq_byte)) | // Abort backoff
        i_tx_done |                                                   // TX complete
        i_too_big                                                     // Frame too big
    );

    assign o_defer_ind = (r_state == ST_IDLE) & i_carrier_sense;

    //============================================================
    // State register
    //============================================================

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state <= ST_DEFER;
            o_state_jam_q <= 1'b0;
        end else begin
            o_state_jam_q <= o_state_jam;
            r_state <= r_next;
        end
    end

    //============================================================
    // State output logic
    //============================================================

    always @(*) begin
        // Default: all states low
        o_state_idle     = 1'b0;
        o_state_ipg      = 1'b0;
        o_state_preamble = 1'b0;
        o_state_data     = 2'b00;
        o_state_pad      = 1'b0;
        o_state_fcs      = 1'b0;
        o_state_jam      = 1'b0;
        o_state_backoff  = 1'b0;
        o_state_defer    = 1'b0;

        case (r_next)
            ST_DEFER:     o_state_defer    = 1'b1;
            ST_IPG:       o_state_ipg      = 1'b1;
            ST_IDLE:      o_state_idle     = 1'b1;
            ST_PREAMBLE:  o_state_preamble = 1'b1;
            ST_DATA:      o_state_data     = 2'b11;  // Assert both data bits
            ST_PAD:       o_state_pad      = 1'b1;
            ST_FCS:       o_state_fcs      = 1'b1;
            ST_JAM:       o_state_jam      = 1'b1;
            ST_BACKOFF:   o_state_backoff  = 1'b1;
            default:      ; // All low
        endcase
    end

    //============================================================
    // Next-state combinational logic
    //============================================================

    always @(*) begin
        r_next = r_state;

        case (r_state)
            ST_DEFER: begin
                if (o_start_ipg)
                    r_next = ST_IPG;
            end

            ST_IPG: begin
                if (o_start_defer)
                    r_next = ST_DEFER;
                else if (w_start_idle)
                    r_next = ST_IDLE;
            end

            ST_IDLE: begin
                if (o_start_defer)
                    r_next = ST_DEFER;
                else if (o_start_preamble)
                    r_next = ST_PREAMBLE;
            end

            ST_PREAMBLE: begin
                if (o_start_jam)
                    r_next = ST_JAM;
                else if (o_start_data[0])
                    r_next = ST_DATA;
            end

            ST_DATA: begin
                if (o_start_jam)
                    r_next = ST_JAM;
                else if (w_start_pad)
                    r_next = ST_PAD;
                else if (o_start_fcs)
                    r_next = ST_FCS;
            end

            ST_PAD: begin
                if (o_start_jam)
                    r_next = ST_JAM;
                else if (o_start_fcs)
                    r_next = ST_FCS;
            end

            ST_FCS: begin
                if (o_start_jam)
                    r_next = ST_JAM;
            end

            ST_JAM: begin
                if (o_start_backoff)
                    r_next = ST_BACKOFF;
                else if (o_start_defer)
                    r_next = ST_DEFER;
            end

            ST_BACKOFF: begin
                if (o_start_defer)
                    r_next = ST_DEFER;
                else if (o_start_preamble)
                    r_next = ST_PREAMBLE;
            end

            default: r_next = ST_DEFER;
        endcase
    end

endmodule
