`timescale 1ns/1ps
//==============================================================================
// Module: eth_tx_pause
// Description: TX PAUSE frame generator (IEEE 802.3x Flow Control)
// Author: Custom Ethernet MAC
// Reference: ethmac eth_transmitcontrol.v
//==============================================================================
//
// Overview:
// --------
// This module generates and transmits PAUSE frames when flow control is enabled.
// A PAUSE frame instructs remote devices to temporarily stop transmitting.
//
// NOTE: CDC (Clock Domain Crossing) is handled in the top-level module.
// This module assumes all inputs are already synchronized to i_mtx_clk domain.
//
// PAUSE Frame Structure (46 bytes):
// ----------------------------------
// Byte 0-5:   01:80:C2:00:00:01  (Reserved Multicast Destination Address)
// Byte 6-11:  Source MAC Address (from MAC_ADDR register)
// Byte 12-13: 88:08              (MAC Control Type)
// Byte 14-15: 00:01              (PAUSE Opcode)
// Byte 16-17: Pause Timer Value  (from TX_FLOW register)
// Byte 18-45: Padding (to meet minimum 64-byte frame)
// Byte 46-49: CRC-32            (added by TX MAC)
//
// Flow:
// -----
// 1. Latch PAUSE request (WillSendControlFrame)
// 2. Wait for TX channel idle
// 3. Assert CtrlMux to select control data
// 4. Generate PAUSE frame data (ByteCnt 0->34)
// 5. Assert TxCtrlEndFrm when complete
// 6. Block TX interrupt during control frame transmission
//
// Removed from original:
// ----------------------
// - DLYCRCEN logic (CRC always calculated after SFD per IEEE 802.3)
//==============================================================================

module eth_tx_pause (
    // Global
    input  wire        i_mtx_clk,
    input  wire        i_hresetn,

    // From register (already synchronized to i_mtx_clk domain)
    input  wire        i_tpause_rq,      // PAUSE request (CDC handled in top)
    input  wire        i_tx_flow,         // TX flow control enable (CDC handled in top)
    input  wire [15:0] i_tx_pause_tv,     // PAUSE timer value (CDC handled in top)
    input  wire [47:0] i_mac_addr,        // Source MAC address (CDC handled in top)

    // TX status (from TX MAC)
    input  wire        i_tx_done,          // TX done
    input  wire        i_tx_abort,         // TX abort
    input  wire        i_tx_start_frm,     // Start normal frame
    input  wire        i_tx_used_data,     // TX MAC consuming data

    // To TX MAC
    output reg         o_tx_ctrl_start,    // Control frame start
    output reg         o_tx_ctrl_end,      // Control frame end
    output reg         o_ctrl_mux,         // Select control data
    output reg         o_sending_ctrl,     // Sending control frame (enables PAD/CRC)
    output wire  [7:0] o_ctrl_data,        // Control frame byte data
    output reg         o_block_tx_done,    // Block TX done interrupt

    // Status
    output reg         o_ctrl_done         // Control frame transmission complete
);

//==============================================================================
// Local parameters
//==============================================================================
localparam BYTE_CNT_MAX = 6'h22;  // 34 - PAUSE frame is 35 bytes (counted twice)

//==============================================================================
// Internal signals
//==============================================================================
reg         r_will_send_ctrl;      // Latched PAUSE request
reg         r_tx_ctrl_start_q;      // Delayed start pulse
reg         r_tx_ctrl_end_q;        // Delayed end pulse
reg         r_tpause_rq_q;          // Delayed request for edge detection
reg         r_tpause_rq_q2;         // Previous request for edge detection

// Byte counter
reg  [5:0]  r_byte_cnt;

// Muxed control data
reg  [7:0]  r_muxed_ctrl_data;
reg  [7:0]  r_ctrl_data_latch;

//==============================================================================
// Edge detector for PAUSE request
// Detects rising edge on i_tpause_rq
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn) begin
        r_tpause_rq_q  <= 1'b0;
        r_tpause_rq_q2 <= 1'b0;
    end else begin
        r_tpause_rq_q  <= i_tpause_rq;
        r_tpause_rq_q2 <= r_tpause_rq_q;
    end
end

wire w_tpause_rq_edge;
assign w_tpause_rq_edge = i_tpause_rq & ~r_tpause_rq_q;  // Rising edge

//==============================================================================
// WillSendControlFrame: Latch PAUSE request
// Cleared when control frame transmission ends
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        r_will_send_ctrl <= 1'b0;
    else if (o_tx_ctrl_end & o_ctrl_mux)
        r_will_send_ctrl <= 1'b0;
    else if (w_tpause_rq_edge & i_tx_flow)
        r_will_send_ctrl <= 1'b1;
end

//==============================================================================
// TxCtrlStartFrm: Generate start frame pulse
// Starts when: will send ctrl frame AND channel is idle
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        o_tx_ctrl_start <= 1'b0;
    else if (r_will_send_ctrl &
             ~i_tx_used_data &
             (i_tx_done | i_tx_abort | i_tx_start_frm))
        o_tx_ctrl_start <= 1'b1;
    else
        o_tx_ctrl_start <= 1'b0;
end

//==============================================================================
// CtrlMux: Control data multiplexer
// When asserted, TX MAC uses control frame data instead of normal data
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        o_ctrl_mux <= 1'b0;
    else if (r_will_send_ctrl & ~i_tx_used_data)
        o_ctrl_mux <= 1'b1;
    else if (i_tx_done)
        o_ctrl_mux <= 1'b0;
end

//==============================================================================
// SendingCtrlFrm: Enable padding and CRC for control frame
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        o_sending_ctrl <= 1'b0;
    else if (r_will_send_ctrl & o_tx_ctrl_start)
        o_sending_ctrl <= 1'b1;
    else if (i_tx_done)
        o_sending_ctrl <= 1'b0;
end

//==============================================================================
// BlockTxDone: Block TX done interrupt during control frame transmission
// Prevents premature TXB_IRQ when switching to control frame
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        o_block_tx_done <= 1'b0;
    else if (o_tx_ctrl_start)
        o_block_tx_done <= 1'b1;
    else if (i_tx_start_frm)
        o_block_tx_done <= 1'b0;
end

//==============================================================================
// Byte counter: Counts bytes in control frame
// Frame is 35 bytes (0x00 to 0x22)
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn) begin
        r_byte_cnt <= 6'h0;
    end else if (~o_tx_ctrl_start & (i_tx_done | i_tx_abort)) begin
        r_byte_cnt <= 6'h0;                    // Reset when frame ends
    end else if (o_ctrl_mux & i_tx_used_data) begin
        r_byte_cnt <= r_byte_cnt + 1'b1;      // Count on each byte consumed
    end
end

// Detect end of control frame (byte count reached 0x22)
wire w_ctrl_end;
assign w_ctrl_end = (r_byte_cnt == BYTE_CNT_MAX);

//==============================================================================
// TxCtrlEndFrm: Generate end frame pulse
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn) begin
        o_tx_ctrl_end   <= 1'b0;
        r_tx_ctrl_end_q <= 1'b0;
    end else begin
        r_tx_ctrl_end_q <= w_ctrl_end;
        o_tx_ctrl_end   <= w_ctrl_end | r_tx_ctrl_end_q;
    end
end

// Control done status
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        o_ctrl_done <= 1'b0;
    else
        o_ctrl_done <= o_tx_ctrl_end;
end

// Delayed start for edge detection
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        r_tx_ctrl_start_q <= 1'b0;
    else
        r_tx_ctrl_start_q <= o_tx_ctrl_start;
end

//==============================================================================
// Control data generation: PAUSE frame byte values
// Reference: IEEE 802.3 Table 31B-1
//==============================================================================
always @(r_byte_cnt or i_mac_addr or i_tx_pause_tv) begin
    case (r_byte_cnt)
        // Destination Address: 01:80:C2:00:00:01 (Reserved Multicast)
        6'h00: r_muxed_ctrl_data = 8'h01;
        6'h01: r_muxed_ctrl_data = 8'h80;
        6'h02: r_muxed_ctrl_data = 8'hC2;
        6'h03: r_muxed_ctrl_data = 8'h00;
        6'h04: r_muxed_ctrl_data = 8'h00;
        6'h05: r_muxed_ctrl_data = 8'h01;

        // Source MAC Address (from register)
        6'h06: r_muxed_ctrl_data = i_mac_addr[47:40];
        6'h07: r_muxed_ctrl_data = i_mac_addr[39:32];
        6'h08: r_muxed_ctrl_data = i_mac_addr[31:24];
        6'h09: r_muxed_ctrl_data = i_mac_addr[23:16];
        6'h0A: r_muxed_ctrl_data = i_mac_addr[15:8];
        6'h0B: r_muxed_ctrl_data = i_mac_addr[7:0];

        // Type/Length: 0x8808 (MAC Control)
        6'h0C: r_muxed_ctrl_data = 8'h88;
        6'h0D: r_muxed_ctrl_data = 8'h08;

        // Opcode: 0x0001 (PAUSE)
        6'h0E: r_muxed_ctrl_data = 8'h00;
        6'h0F: r_muxed_ctrl_data = 8'h01;

        // PAUSE Timer Value (from register)
        6'h10: r_muxed_ctrl_data = i_tx_pause_tv[15:8];
        6'h11: r_muxed_ctrl_data = i_tx_pause_tv[7:0];

        // Padding (bytes 18-33): zeros for minimum frame size
        6'h12,
        6'h13,
        6'h14,
        6'h15,
        6'h16,
        6'h17,
        6'h18,
        6'h19,
        6'h1A,
        6'h1B,
        6'h1C,
        6'h1D,
        6'h1E,
        6'h1F,
        6'h20,
        6'h21,
        6'h22: r_muxed_ctrl_data = 8'h00;

        default: r_muxed_ctrl_data = 8'h00;
    endcase
end

//==============================================================================
// Control data latch: Latch data on even byte boundary
// Ensures stable data during TX MAC operation
//==============================================================================
always @(posedge i_mtx_clk or negedge i_hresetn) begin
    if (!i_hresetn)
        r_ctrl_data_latch <= 8'h00;
    else if (~r_byte_cnt[0])          // Latch on even byte (0, 2, 4...)
        r_ctrl_data_latch <= r_muxed_ctrl_data;
end

assign o_ctrl_data = r_ctrl_data_latch;

endmodule
