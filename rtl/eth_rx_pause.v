`timescale 1ns/1ps

//------------------------------------------------------------------------------
// RX PAUSE timer
//
// Chuc nang:
// - Nhan event PAUSE frame tu RX clock domain.
// - Dong bo event sang TX clock domain bang toggle CDC.
// - Load pause timer trong TX clock domain.
// - Tao o_pause_active de TX path tam dung normal frame khi remote yeu cau.
//
// Ghi chu:
// - Module nay khong parse PAUSE frame. eth_rx_buffer_ctrl lam viec do.
// - i_pause_time_rx phai on dinh khi i_pause_seen_rx pulse.
//------------------------------------------------------------------------------
module eth_rx_pause (
    input  wire        i_rx_clk,
    input  wire        i_tx_clk,
    input  wire        i_rst_n,

    input  wire        i_rx_pause_en,
    input  wire        i_pause_seen_rx,
    input  wire [15:0] i_pause_time_rx,

    output reg         o_pause_seen_pulse_rx,
    output wire        o_pause_seen_pulse_tx,
    output wire        o_pause_active_tx
);

    reg        r_toggle_rx;
    reg [15:0] r_pause_time_hold_rx;

    reg        r_toggle_tx_s1;
    reg        r_toggle_tx_s2;
    reg        r_toggle_tx_s3;
    reg [15:0] r_pause_time_tx_s1;
    reg [15:0] r_pause_time_tx_s2;

    reg [15:0] r_pause_timer_tx;
    reg [8:0]  r_quanta_cnt;

    wire       w_pause_event_tx;
    wire       w_quanta_tick;

    // RX domain: latch pause request.
    always @(posedge i_rx_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_toggle_rx <= 1'b0;
            r_pause_time_hold_rx <= 16'd0;
            o_pause_seen_pulse_rx <= 1'b0;
        end else begin
            o_pause_seen_pulse_rx <= 1'b0;

            if (i_pause_seen_rx) begin
                o_pause_seen_pulse_rx <= 1'b1;

                if (i_rx_pause_en) begin
                    r_pause_time_hold_rx <= i_pause_time_rx;
                    r_toggle_rx <= ~r_toggle_rx;
                end
            end
        end
    end

    // TX domain CDC.
    always @(posedge i_tx_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_toggle_tx_s1 <= 1'b0;
            r_toggle_tx_s2 <= 1'b0;
            r_toggle_tx_s3 <= 1'b0;
            r_pause_time_tx_s1 <= 16'd0;
            r_pause_time_tx_s2 <= 16'd0;
        end else begin
            r_toggle_tx_s1 <= r_toggle_rx;
            r_toggle_tx_s2 <= r_toggle_tx_s1;
            r_toggle_tx_s3 <= r_toggle_tx_s2;

            r_pause_time_tx_s1 <= r_pause_time_hold_rx;
            r_pause_time_tx_s2 <= r_pause_time_tx_s1;
        end
    end

    assign w_pause_event_tx = r_toggle_tx_s2 ^ r_toggle_tx_s3;
    assign o_pause_seen_pulse_tx = w_pause_event_tx;

    // One pause quanta = 512 bit-times.
    // TX MII clock emits 4 bits per clock, so 512 bit-times = 128 clocks.
    assign w_quanta_tick = (r_quanta_cnt == 9'd127);

    always @(posedge i_tx_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_pause_timer_tx <= 16'd0;
            r_quanta_cnt <= 9'd0;
        end else if (w_pause_event_tx) begin
            r_pause_timer_tx <= r_pause_time_tx_s2;
            r_quanta_cnt <= 9'd0;
        end else if (r_pause_timer_tx != 16'd0) begin
            if (w_quanta_tick) begin
                r_pause_timer_tx <= r_pause_timer_tx - 16'd1;
                r_quanta_cnt <= 9'd0;
            end else begin
                r_quanta_cnt <= r_quanta_cnt + 9'd1;
            end
        end else begin
            r_quanta_cnt <= 9'd0;
        end
    end

    assign o_pause_active_tx = (r_pause_timer_tx != 16'd0);

endmodule
