// eth_rx_controller.v
// RX State Machine for IEEE 802.3 frame reception
// Based on ethmac eth_rxstatem.v
// Simplified for 10/100 MAC (no MII management)

`timescale 1ns/1ps

module eth_rx_controller (
    // Global
    input wire              i_clk,
    input wire              i_rst_n,

    // MII signals
    input wire              i_rx_dv,              // RX data valid from PHY
    input wire  [3:0]      i_rx_data,            // RX data nibble

    // Counters (from eth_rx_cnt)
    input wire              i_byte_eq_0,          // Byte count = 0
    input wire              i_byte_max_frame,      // Byte count = MAXFL (1518)
    input wire              i_ifg_eq_24,           // IFG counter = 24

    // Control
    input wire              i_transmitting,        // TX MAC is transmitting (collision check)
    input wire              i_rx_en,               // RX enable from MAC_CTRL

    // State outputs
    output reg              o_state_idle,
    output reg              o_state_drop,
    output reg              o_state_preamble,
    output reg              o_state_sfd,
    output reg  [1:0]      o_state_data,

    // Next-state flags
    output wire             o_start_preamble,
    output wire             o_start_sfd,
    output wire             o_start_data,
    output wire             o_rx_abort             // Abort current frame
);

    //============================================================
    // Constants (per IEEE 802.3)
    //============================================================
    localparam IFG_BIT_TIMES      = 24;        // Inter-Frame Gap (bit times)
    localparam MAX_FRAME_BYTES    = 1518;      // Max frame size (without preamble/SFD)
    localparam MIN_FRAME_BYTES    = 64;        // Min frame size (without preamble/SFD)
    localparam PREAMBLE_BYTES     = 7;         // Preamble size
    localparam SFD_BYTE          = 8'hD5;     // Start Frame Delimiter

    //============================================================
    // FSM state encoding
    //============================================================
    localparam [2:0]
        ST_DROP     = 3'd0,
        ST_IDLE     = 3'd1,
        ST_PREAMBLE = 3'd2,
        ST_SFD      = 3'd3,
        ST_DATA     = 3'd4;

    reg [2:0] r_state;
    reg [2:0] r_next;

    // Internal signals
    wire w_rx_data_eq_5;    // RX data = 0x5 (preamble byte)
    wire w_rx_data_eq_d;    // RX data = 0xD (SFD)
    wire w_rx_active;       // MRxDV asserted
    wire w_carrier_sense;   // TX transmitting (collision in HDX)

    //============================================================
    // Derived signals
    //============================================================

    // Byte detection (need 2 nibbles for 1 byte)
    assign w_rx_data_eq_5 = (i_rx_data == 4'h5);
    assign w_rx_data_eq_d = (i_rx_data == 4'hD);
    assign w_rx_active = i_rx_dv & i_rx_en;
    assign w_carrier_sense = i_transmitting;

    //============================================================
    // Next-state logic
    //============================================================

    // StartPreamble: MRxDV=1, data!=0x5, IDLE, not transmitting
    assign o_start_preamble = w_rx_active & ~w_rx_data_eq_5 &
                              (r_state == ST_IDLE) & ~w_carrier_sense;

    // StartSFD: MRxDV=1, data=0x5, from IDLE or PREAMBLE
    assign o_start_sfd = w_rx_active & w_rx_data_eq_5 &
                         ((r_state == ST_IDLE & ~w_carrier_sense) |
                          (r_state == ST_PREAMBLE));

    // StartData: MRxDV=1, from SFD with IFG satisfied, or continuing
    // Note: ~i_byte_max_frame added to stop Data state when MaxFL reached
    assign o_start_data = w_rx_active &
                          ((r_state == ST_SFD & w_rx_data_eq_d & i_ifg_eq_24) |
                           (r_state == ST_DATA & ~i_byte_max_frame));

    // RxAbort (drop frame): various error conditions
    assign o_rx_abort = w_rx_active &
                        (
                            // Collision detected (HDX): TX active while receiving
                            ((r_state == ST_IDLE) & w_carrier_sense) |
                            // IFG violation during SFD
                            ((r_state == ST_SFD) & ~i_ifg_eq_24 & w_rx_data_eq_d) |
                            // Frame too long
                            ((r_state == ST_DATA) & i_byte_max_frame)
                        );

    //============================================================
    // State register
    //============================================================

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_state <= ST_DROP;
        else
            r_state <= r_next;
    end

    //============================================================
    // State output logic
    //============================================================

    always @(*) begin
        // Default: all states low
        o_state_idle     = 1'b0;
        o_state_drop     = 1'b0;
        o_state_preamble = 1'b0;
        o_state_sfd      = 1'b0;
        o_state_data     = 2'b00;

        case (r_state)
            ST_DROP:     o_state_drop     = 1'b1;
            ST_IDLE:     o_state_idle    = 1'b1;
            ST_PREAMBLE: o_state_preamble = 1'b1;
            ST_SFD:      o_state_sfd     = 1'b1;
            ST_DATA:     o_state_data    = 2'b11;  // Assert both data bits
        endcase
    end

    //============================================================
    // Next-state combinational logic
    //============================================================

    always @(*) begin
        r_next = r_state;

        case (r_state)
            ST_DROP: begin
                // Exit DROP when MRxDV goes low
                if (~i_rx_dv)
                    r_next = ST_IDLE;
            end

            ST_IDLE: begin
                if (o_rx_abort)
                    r_next = ST_DROP;
                else if (o_start_sfd)
                    r_next = ST_SFD;
                else if (o_start_preamble)
                    r_next = ST_PREAMBLE;
            end

            ST_PREAMBLE: begin
                if (o_rx_abort)
                    r_next = ST_DROP;
                else if (o_start_sfd)
                    r_next = ST_SFD;
            end

            ST_SFD: begin
                if (o_rx_abort)
                    r_next = ST_DROP;
                else if (o_start_data)
                    r_next = ST_DATA;
            end

            ST_DATA: begin
                if (o_rx_abort)
                    r_next = ST_DROP;
                else if (~i_rx_dv)
                    // Frame ended normally
                    r_next = ST_IDLE;
            end

            default: r_next = ST_IDLE;
        endcase
    end

endmodule
