`timescale 1ns/1ps

//------------------------------------------------------------------------------
// TX PAUSE frame controller
//
// Chuc nang:
// - Dong bo pause request level tu RX side sang TX clock.
// - Khi pause request doi trang thai, yeu cau top cho quyen gui PAUSE frame.
// - Tao byte stream PAUSE frame cho eth_tx_mac.
// - PAUSE request = 1 gui pause time FFFF.
// - PAUSE request = 0 gui pause time 0000 de release remote.
//
// Module nay khong tu mux voi normal TX data. Top-level se uu tien PAUSE frame
// khi o_pause_request = 1 va TX MAC dang idle.
//------------------------------------------------------------------------------
module eth_tx_pause #(
    parameter [15:0] PAUSE_TIME = 16'hFFFF
) (
    input  wire        i_clk,
    input  wire        i_rst_n,

    input  wire        i_tx_pause_en,
    input  wire        i_pause_req_rx,
    input  wire [47:0] i_mac_sa,

    input  wire        i_start,

    output wire        o_pause_req_tx,
    output wire        o_pause_request,
    output wire        o_active,

    output wire        o_mac_start,
    output wire        o_mac_end,
    output reg  [7:0]  o_mac_data,
    output wire        o_mac_pad_en,
    output wire        o_mac_crc_en,
    output wire        o_mac_underrun,

    input  wire        i_mac_used_data,
    input  wire        i_mac_done,
    input  wire        i_mac_retry,
    input  wire        i_mac_abort,

    output reg         o_pause_done_pulse,
    output reg         o_pause_err_pulse
);

    localparam [1:0]
        ST_IDLE        = 2'd0,
        ST_SEND        = 2'd1,
        ST_RESTART_GAP = 2'd2;

    localparam [47:0] PAUSE_DA     = 48'h0180C2000001;
    localparam [15:0] PAUSE_TYPE   = 16'h8808;
    localparam [15:0] PAUSE_OPCODE = 16'h0001;
    localparam [5:0]  LAST_BYTE    = 6'd17;

    reg [1:0]  r_state;
    reg [5:0]  r_byte_index;
    reg        r_sent_pause_level;
    reg        r_frame_pause_level;
    reg [15:0] r_frame_pause_time;

    reg        r_pause_req_s1;
    reg        r_pause_req_s2;
    reg        r_pause_req_s3;

    reg        r_mac_done_d;
    reg        r_mac_retry_d;
    reg        r_mac_abort_d;

    wire       w_mac_done_pulse;
    wire       w_mac_retry_pulse;
    wire       w_mac_abort_pulse;
    wire       w_desired_pause_level;
    wire       w_need_send;

    // Level CDC tu RX side sang TX clock.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_pause_req_s1 <= 1'b0;
            r_pause_req_s2 <= 1'b0;
            r_pause_req_s3 <= 1'b0;
        end else begin
            r_pause_req_s1 <= i_pause_req_rx;
            r_pause_req_s2 <= r_pause_req_s1;
            r_pause_req_s3 <= r_pause_req_s2;
        end
    end

    assign o_pause_req_tx = r_pause_req_s3;
    assign w_desired_pause_level = i_tx_pause_en & r_pause_req_s3;
    assign w_need_send = (w_desired_pause_level != r_sent_pause_level);
    assign o_pause_request = (r_state == ST_IDLE) & w_need_send;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_done_d <= 1'b0;
            r_mac_retry_d <= 1'b0;
            r_mac_abort_d <= 1'b0;
        end else begin
            r_mac_done_d <= i_mac_done;
            r_mac_retry_d <= i_mac_retry;
            r_mac_abort_d <= i_mac_abort;
        end
    end

    assign w_mac_done_pulse  = i_mac_done  & ~r_mac_done_d;
    assign w_mac_retry_pulse = i_mac_retry & ~r_mac_retry_d;
    assign w_mac_abort_pulse = i_mac_abort & ~r_mac_abort_d;

    // Byte mux cho PAUSE frame, byte lon truoc.
    always @(*) begin
        case (r_byte_index)
            6'd0:  o_mac_data = PAUSE_DA[47:40];
            6'd1:  o_mac_data = PAUSE_DA[39:32];
            6'd2:  o_mac_data = PAUSE_DA[31:24];
            6'd3:  o_mac_data = PAUSE_DA[23:16];
            6'd4:  o_mac_data = PAUSE_DA[15:8];
            6'd5:  o_mac_data = PAUSE_DA[7:0];
            6'd6:  o_mac_data = i_mac_sa[47:40];
            6'd7:  o_mac_data = i_mac_sa[39:32];
            6'd8:  o_mac_data = i_mac_sa[31:24];
            6'd9:  o_mac_data = i_mac_sa[23:16];
            6'd10: o_mac_data = i_mac_sa[15:8];
            6'd11: o_mac_data = i_mac_sa[7:0];
            6'd12: o_mac_data = PAUSE_TYPE[15:8];
            6'd13: o_mac_data = PAUSE_TYPE[7:0];
            6'd14: o_mac_data = PAUSE_OPCODE[15:8];
            6'd15: o_mac_data = PAUSE_OPCODE[7:0];
            6'd16: o_mac_data = r_frame_pause_time[15:8];
            6'd17: o_mac_data = r_frame_pause_time[7:0];
            default: o_mac_data = 8'h00;
        endcase
    end

    assign o_active = (r_state != ST_IDLE);
    assign o_mac_start = (r_state == ST_SEND);
    assign o_mac_end = (r_state == ST_SEND) & (r_byte_index == LAST_BYTE);
    assign o_mac_pad_en = 1'b1;
    assign o_mac_crc_en = 1'b1;
    assign o_mac_underrun = 1'b0;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state <= ST_IDLE;
            r_byte_index <= 6'd0;
            r_sent_pause_level <= 1'b0;
            r_frame_pause_level <= 1'b0;
            r_frame_pause_time <= 16'd0;
            o_pause_done_pulse <= 1'b0;
            o_pause_err_pulse <= 1'b0;
        end else begin
            o_pause_done_pulse <= 1'b0;
            o_pause_err_pulse <= 1'b0;

            case (r_state)
                ST_IDLE: begin
                    r_byte_index <= 6'd0;

                    if (i_start & w_need_send) begin
                        r_frame_pause_level <= w_desired_pause_level;
                        r_frame_pause_time <= w_desired_pause_level ? PAUSE_TIME : 16'd0;
                        r_state <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (w_mac_abort_pulse) begin
                        o_pause_err_pulse <= 1'b1;
                        r_byte_index <= 6'd0;
                        r_state <= ST_IDLE;
                    end else if (w_mac_retry_pulse) begin
                        r_byte_index <= 6'd0;
                        r_state <= ST_RESTART_GAP;
                    end else if (w_mac_done_pulse) begin
                        o_pause_done_pulse <= 1'b1;
                        r_sent_pause_level <= r_frame_pause_level;
                        r_byte_index <= 6'd0;
                        r_state <= ST_IDLE;
                    end else if (i_mac_used_data & (r_byte_index != LAST_BYTE)) begin
                        r_byte_index <= r_byte_index + 6'd1;
                    end
                end

                ST_RESTART_GAP: begin
                    r_state <= ST_SEND;
                end

                default: begin
                    r_state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
