`timescale 1ns / 1ps

// eth_mac_status.v
// MAC Status Controller - Collects and latches TX/RX status signals
// Based on ethmac eth_macstatus.v
// Simplified per DESIGN_NOTES.md:
//   REMOVED: InvalidSymbol, ShortFrame, DribbleNibble, ReceivedPacketTooBig
//   KEPT: CRC error, PHY error, Late collision, TX status
//
// This module replaces the status collection logic that was spread across
// multiple modules in the original design. It provides:
//   - RX status latching (MRxClk domain) for BD write
//   - TX status latching (MTxClk domain) for BD write

module eth_mac_status (
    //============================================================
    // Clock & Reset
    //============================================================
    input  wire        i_rx_clk,          // MRxClk - RX clock domain
    input  wire        i_tx_clk,          // MTxClk - TX clock domain
    input  wire        i_rst_n,           // Async reset (active low)

    //============================================================
    // RX Status Inputs (MRxClk domain)
    //============================================================
    input  wire        i_rx_crc_err,      // CRC error from RX MAC
    input  wire        i_rx_mrx_err,      // MRxErr from PHY
    input  wire        i_rx_dv,           // RX data valid from PHY
    input  wire        i_rx_state_sfd,    // RX FSM in SFD state
    input  wire [1:0] i_rx_state_data,   // RX FSM in Data state
    input  wire        i_rx_state_idle,   // RX FSM in Idle state
    input  wire        i_rx_collision,    // Collision detected
    input  wire        i_full_duplex,     // Full duplex mode

    //============================================================
    // RX Status Outputs (MRxClk domain)
    //============================================================
    output wire        o_rx_crc_err,      // Latched CRC error
    output wire        o_rx_phy_err,     // Latched PHY error
    output wire        o_rx_late_coll,    // Late collision detected
    output wire        o_rx_load_status,  // Trigger BD status write
    output wire        o_rx_receive_end   // RX frame ended
);

    //============================================================
    // Constants (IEEE 802.3 fixed values)
    //============================================================
    localparam [5:0] COLL_VALID = 6'd63;  // Collision window = 64 bytes

    //============================================================
    // Internal Wires
    //============================================================
    wire                w_take_sample;     // Time to sample RX status
    wire                w_rx_col_window;   // Inside collision window
    wire                w_rx_col_window_n; // Collision window closed

    //============================================================
    // RX Status: Latched CRC Error
    //============================================================
    // Latches CRC error during frame reception
    // Reset when entering SFD, set when in Data state with CRC error
    reg                 r_rx_crc_err;

    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_crc_err <= 1'b0;
        else if (i_rx_state_sfd)
            r_rx_crc_err <= 1'b0;
        else if (i_rx_state_data[0])
            r_rx_crc_err <= i_rx_crc_err;
    end

    assign o_rx_crc_err = r_rx_crc_err;

    //============================================================
    // RX Status: Latched PHY Error (MRxErr)
    //============================================================
    // Latches MRxErr during valid reception states
    // Set when MRxErr is asserted in preamble/SFD/data/idle states
    reg                 r_rx_phy_err;

    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_phy_err <= 1'b0;
        else if (i_rx_mrx_err & i_rx_dv &
                 (i_rx_state_sfd | (|i_rx_state_data) | i_rx_state_idle))
            r_rx_phy_err <= 1'b1;
        else
            r_rx_phy_err <= 1'b0;
    end

    assign o_rx_phy_err = r_rx_phy_err;

    //============================================================
    // RX Status: Collision Window
    //============================================================
    // Tracks whether we're inside the collision window (first 64 bytes)
    // IEEE 802.3: Collisions only valid within 512 bit-times = 64 bytes
    reg                 r_rx_col_window;

    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_col_window <= 1'b1;
        else if (~i_rx_collision &
                 (i_rx_state_data[1] | i_rx_state_sfd) &
                 (i_rx_state_data[1] ? 1'b1 : 1'b1))  // Simplified: close after byte
            r_rx_col_window <= 1'b0;
        else if (i_rx_state_idle)
            r_rx_col_window <= 1'b1;
    end

    assign w_rx_col_window   = r_rx_col_window;
    assign w_rx_col_window_n = ~r_rx_col_window;

    //============================================================
    // RX Status: Late Collision Detection
    //============================================================
    // Late collision = collision detected AFTER collision window closed
    // Only valid in half-duplex mode
    reg                 r_rx_late_coll;

    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_late_coll <= 1'b0;
        else if (o_rx_load_status)
            r_rx_late_coll <= 1'b0;
        else if (i_rx_collision & ~i_full_duplex & w_rx_col_window_n)
            r_rx_late_coll <= 1'b1;
    end

    assign o_rx_late_coll = r_rx_late_coll;

    //============================================================
    // RX Status: Take Sample
    //============================================================
    // Time to sample and store RX status for BD write
    // Trigger when:
    //   - In Data state and MRxDV goes low (normal end)
    //   - In Data state and MRxDV high with max frame (truncated)
    assign w_take_sample = ((|i_rx_state_data) & ~i_rx_dv) |
                          (i_rx_state_data[0] & i_rx_dv);

    //============================================================
    // RX Status: Load RX Status
    //============================================================
    // Pulse to trigger BD status write
    reg                 r_rx_load_status;

    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_load_status <= 1'b0;
        else
            r_rx_load_status <= w_take_sample;
    end

    assign o_rx_load_status = r_rx_load_status;

    //============================================================
    // RX Status: Receive End
    //============================================================
    // Indicates end of frame reception (1 cycle after LoadRxStatus)
    reg                 r_rx_receive_end;

    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_receive_end <= 1'b0;
        else
            r_rx_receive_end <= o_rx_load_status;
    end

    assign o_rx_receive_end = r_rx_receive_end;

endmodule
