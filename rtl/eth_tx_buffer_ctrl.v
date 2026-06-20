`timescale 1ns/1ps

//------------------------------------------------------------------------------
// TX buffer controller
//
// Chuc nang:
// - Nhan frame pending tu eth_tx_frame_buffer.
// - Ghep DA + SA + LEN + payload thanh luong byte cho eth_tx_mac.
// - Payload doc tu buffer RAM co latency 1 chu ky nen controller co prefetch.
// - Neu eth_tx_mac bao retry, controller tua ve dau frame va doc lai payload.
// - Padding va CRC luon bat.
//------------------------------------------------------------------------------
module eth_tx_buffer_ctrl #(
    parameter ADDR_WIDTH = 9
) (
    input  wire                  i_clk,
    input  wire                  i_rst_n,

    input  wire                  i_tx_en,
    input  wire [47:0]           i_mac_sa,

    // Tu eth_tx_frame_buffer.
    input  wire                  i_frame_valid,
    input  wire [15:0]           i_frame_len,
    input  wire [47:0]           i_frame_da,
    input  wire [9:0]            i_frame_words,
    output reg                   o_frame_take,

    output reg  [ADDR_WIDTH-1:0] o_buf_rd_addr,
    output reg                   o_buf_rd_en,
    input  wire [31:0]           i_buf_rd_data,

    output reg                   o_tx_done_pulse,
    output reg                   o_tx_err_pulse,

    // Sang eth_tx_mac.
    output wire                  o_mac_start,
    output wire                  o_mac_end,
    output reg  [7:0]            o_mac_data,
    output wire                  o_mac_pad_en,
    output wire                  o_mac_crc_en,
    output wire                  o_mac_underrun,

    input  wire                  i_mac_used_data,
    input  wire                  i_mac_retry,
    input  wire                  i_mac_abort,
    input  wire                  i_mac_done,

    output wire                  o_busy
);

    //--------------------------------------------------------------------------
    // Ma trang thai
    //--------------------------------------------------------------------------
    localparam [2:0]
        ST_IDLE       = 3'd0,
        ST_WAIT_TAKE  = 3'd1,
        ST_READ_FIRST = 3'd2,
        ST_WAIT_FIRST = 3'd3,
        ST_SEND       = 3'd4,
        ST_RESTART_GAP = 3'd5;

    localparam [15:0] HEADER_BYTES = 16'd14;

    reg [2:0] r_state;

    //--------------------------------------------------------------------------
    // Metadata frame dang gui
    //--------------------------------------------------------------------------
    reg [15:0] r_frame_len;
    reg [47:0] r_frame_da;
    reg [47:0] r_frame_sa;
    reg [9:0]  r_frame_words;

    wire [15:0] w_total_bytes = HEADER_BYTES + r_frame_len;
    wire [15:0] w_last_byte_index = w_total_bytes - 16'd1;

    //--------------------------------------------------------------------------
    // Payload prefetch
    //--------------------------------------------------------------------------
    reg [15:0] r_byte_index;
    reg [15:0] r_payload_byte_index;
    reg [9:0]  r_next_rd_word_index;
    reg [31:0] r_cur_word;
    reg [31:0] r_next_word;
    reg        r_next_word_valid;

    // Frame buffer tra data bang output register. Sau khi phat rd_en,
    // cho 2 canh clock roi moi bat i_buf_rd_data de tranh data cu.
    reg [1:0]  r_rd_wait;
    reg        r_rd_first;

    wire        w_in_payload = (r_byte_index >= HEADER_BYTES);
    wire [1:0]  w_payload_byte_sel = r_payload_byte_index[1:0];
    wire        w_payload_word_last_byte = (r_payload_byte_index[1:0] == 2'b11);
    wire        w_has_more_word = (r_next_rd_word_index < r_frame_words);
    wire        w_more_payload_after_byte =
                ((r_payload_byte_index + 16'd1) < r_frame_len);

    //--------------------------------------------------------------------------
    // Bat suon status tu eth_tx_mac
    //--------------------------------------------------------------------------
    reg r_mac_retry_d;
    reg r_mac_abort_d;
    reg r_mac_done_d;

    wire w_mac_retry_pulse = i_mac_retry & ~r_mac_retry_d;
    wire w_mac_abort_pulse = i_mac_abort & ~r_mac_abort_d;
    wire w_mac_done_pulse  = i_mac_done  & ~r_mac_done_d;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_retry_d <= 1'b0;
            r_mac_abort_d <= 1'b0;
            r_mac_done_d  <= 1'b0;
        end else begin
            r_mac_retry_d <= i_mac_retry;
            r_mac_abort_d <= i_mac_abort;
            r_mac_done_d  <= i_mac_done;
        end
    end

    //--------------------------------------------------------------------------
    // Byte mux: DA, SA, LEN va payload deu gui byte lon truoc.
    //--------------------------------------------------------------------------
    always @(*) begin
        case (r_byte_index)
            16'd0:  o_mac_data = r_frame_da[47:40];
            16'd1:  o_mac_data = r_frame_da[39:32];
            16'd2:  o_mac_data = r_frame_da[31:24];
            16'd3:  o_mac_data = r_frame_da[23:16];
            16'd4:  o_mac_data = r_frame_da[15:8];
            16'd5:  o_mac_data = r_frame_da[7:0];
            16'd6:  o_mac_data = r_frame_sa[47:40];
            16'd7:  o_mac_data = r_frame_sa[39:32];
            16'd8:  o_mac_data = r_frame_sa[31:24];
            16'd9:  o_mac_data = r_frame_sa[23:16];
            16'd10: o_mac_data = r_frame_sa[15:8];
            16'd11: o_mac_data = r_frame_sa[7:0];
            16'd12: o_mac_data = r_frame_len[15:8];
            16'd13: o_mac_data = r_frame_len[7:0];
            default: begin
                case (w_payload_byte_sel)
                    2'd0: o_mac_data = r_cur_word[31:24];
                    2'd1: o_mac_data = r_cur_word[23:16];
                    2'd2: o_mac_data = r_cur_word[15:8];
                    default: o_mac_data = r_cur_word[7:0];
                endcase
            end
        endcase
    end

    assign o_busy = (r_state != ST_IDLE);
    assign o_mac_start = (r_state == ST_SEND);
    // End phai dung cung luc byte cuoi dang duoc giu tren o_mac_data.
    // Neu chi bat end sau khi MAC consume byte cuoi thi MAC co the phat du 1 byte.
    assign o_mac_end = (r_state == ST_SEND) & (r_byte_index == w_last_byte_index);
    assign o_mac_pad_en = 1'b1;
    assign o_mac_crc_en = 1'b1;
    assign o_mac_underrun = 1'b0;

    //--------------------------------------------------------------------------
    // FSM chinh
    //--------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state <= ST_IDLE;

            r_frame_len <= 16'd0;
            r_frame_da <= 48'd0;
            r_frame_sa <= 48'd0;
            r_frame_words <= 10'd0;
            r_byte_index <= 16'd0;
            r_payload_byte_index <= 16'd0;
            r_next_rd_word_index <= 10'd0;
            r_cur_word <= 32'd0;
            r_next_word <= 32'd0;
            r_next_word_valid <= 1'b0;
            r_rd_wait <= 2'd0;
            r_rd_first <= 1'b0;

            o_frame_take <= 1'b0;
            o_buf_rd_addr <= {ADDR_WIDTH{1'b0}};
            o_buf_rd_en <= 1'b0;
            o_tx_done_pulse <= 1'b0;
            o_tx_err_pulse <= 1'b0;
        end else begin
            o_frame_take <= 1'b0;
            o_buf_rd_en <= 1'b0;
            o_tx_done_pulse <= 1'b0;
            o_tx_err_pulse <= 1'b0;

            if (r_rd_wait != 2'd0) begin
                if (r_rd_wait == 2'd1) begin
                    r_rd_wait <= 2'd0;

                    if (r_rd_first) begin
                        r_cur_word <= i_buf_rd_data;
                        r_rd_first <= 1'b0;
                        if (r_state == ST_WAIT_FIRST)
                            r_state <= ST_SEND;
                    end else begin
                        r_next_word <= i_buf_rd_data;
                        r_next_word_valid <= 1'b1;
                    end
                end else begin
                    r_rd_wait <= r_rd_wait - 2'd1;
                end
            end

            case (r_state)
                ST_IDLE: begin
                    r_byte_index <= 16'd0;
                    r_payload_byte_index <= 16'd0;
                    r_next_rd_word_index <= 10'd0;
                    r_next_word_valid <= 1'b0;
                    r_rd_wait <= 2'd0;
                    r_rd_first <= 1'b0;

                    if (i_tx_en & i_frame_valid) begin
                        o_frame_take <= 1'b1;
                        r_frame_len <= i_frame_len;
                        r_frame_da <= i_frame_da;
                        r_frame_sa <= i_mac_sa;
                        r_frame_words <= i_frame_words;

                        r_state <= ST_WAIT_TAKE;
                    end
                end

                ST_WAIT_TAKE: begin
                    if (!i_tx_en) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if ((r_frame_len != 16'd0) & (r_frame_words == 10'd0)) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if (r_frame_len != 16'd0) begin
                        r_state <= ST_READ_FIRST;
                    end else begin
                        r_state <= ST_SEND;
                    end
                end

                ST_READ_FIRST: begin
                    if (!i_tx_en) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else begin
                        o_buf_rd_addr <= {ADDR_WIDTH{1'b0}};
                        o_buf_rd_en <= 1'b1;
                        r_rd_wait <= 2'd2;
                        r_rd_first <= 1'b1;
                        r_next_rd_word_index <= 10'd1;
                        r_state <= ST_WAIT_FIRST;
                    end
                end

                ST_WAIT_FIRST: begin
                    if (!i_tx_en) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end
                end

                ST_RESTART_GAP: begin
                    if (!i_tx_en) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if ((r_frame_len != 16'd0) & (r_frame_words == 10'd0)) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if (r_frame_len != 16'd0) begin
                        r_state <= ST_READ_FIRST;
                    end else begin
                        r_state <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (!i_tx_en) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if (w_mac_abort_pulse) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_err_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if (w_mac_done_pulse) begin
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        o_tx_done_pulse <= 1'b1;
                        r_state <= ST_IDLE;
                    end else if (w_mac_retry_pulse) begin
                        r_byte_index <= 16'd0;
                        r_payload_byte_index <= 16'd0;
                        r_next_rd_word_index <= 10'd0;
                        r_next_word_valid <= 1'b0;
                        r_rd_wait <= 2'd0;
                        r_rd_first <= 1'b0;
                        r_state <= ST_RESTART_GAP;
                    end else if (i_mac_used_data) begin
                        if (w_in_payload) begin
                            if ((w_payload_byte_sel == 2'b00) & w_has_more_word &
                                (r_rd_wait == 2'd0) & ~r_next_word_valid) begin
                                o_buf_rd_addr <= r_next_rd_word_index[ADDR_WIDTH-1:0];
                                o_buf_rd_en <= 1'b1;
                                r_rd_wait <= 2'd2;
                                r_rd_first <= 1'b0;
                                r_next_rd_word_index <= r_next_rd_word_index + 10'd1;
                            end

                            if (w_payload_word_last_byte) begin
                                if (r_next_word_valid) begin
                                    r_cur_word <= r_next_word;
                                    r_next_word_valid <= 1'b0;
                                end else if (w_more_payload_after_byte) begin
                                    r_rd_wait <= 2'd0;
                                    r_rd_first <= 1'b0;
                                    o_tx_err_pulse <= 1'b1;
                                    r_state <= ST_IDLE;
                                end
                            end

                            if (r_payload_byte_index < r_frame_len)
                                r_payload_byte_index <= r_payload_byte_index + 16'd1;
                        end

                        if (r_byte_index < w_last_byte_index)
                            r_byte_index <= r_byte_index + 16'd1;
                    end
                end

                default: begin
                    r_state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
