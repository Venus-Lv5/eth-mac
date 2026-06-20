`timescale 1ns/1ps

//------------------------------------------------------------------------------
// RX ping-pong frame buffer
//
// Chuc nang:
// - RX clock ghi payload hop le vao 1 trong 2 buffer RAM noi bo.
// - Moi buffer giu dung 1 frame payload.
// - AHB clock doc frame theo dung thu tu nhan qua RX_DATA.
// - Khi ca 2 buffer deu day, request PAUSE FFFF va frame moi bi drop.
//
// Luu y:
// - Module nay khong parse DA/LEN/CRC. RX controller ben ngoai lam viec do.
// - RX controller chi commit frame khi DA/LEN/CRC hop le.
// - Payload RAM co 1 port ghi RX clock va 1 port doc AHB clock.
//------------------------------------------------------------------------------
module eth_rx_frame_buffer #(
    parameter MAX_PAYLOAD_BYTES = 1500,
    parameter BUFFER_WORDS      = 375,
    parameter ADDR_WIDTH        = 9
) (
    // RX clock domain.
    input  wire                    i_rx_clk,
    input  wire                    i_rx_rst_n,
    input  wire                    i_rx_en,

    input  wire                    i_rx_frame_start,
    input  wire                    i_rx_payload_wr_en,
    input  wire [31:0]             i_rx_payload_wdata,
    input  wire [1:0]              i_rx_payload_byte_valid,
    input  wire                    i_rx_frame_commit,
    input  wire                    i_rx_frame_drop,
    input  wire [15:0]             i_rx_frame_len,

    output wire                    o_rx_can_accept,
    output reg                     o_rx_busy_pulse,
    output reg                     o_rx_err_pulse,
    output wire                    o_rx_pause_req,

    // AHB/register clock domain.
    input  wire                    i_ahb_clk,
    input  wire                    i_ahb_rst_n,

    output wire                    o_ahb_rx_avail,
    output wire [15:0]             o_ahb_rx_len,
    output wire [9:0]              o_ahb_rx_words,
    input  wire                    i_ahb_rx_rd_en,
    output reg  [31:0]             o_ahb_rx_rdata,
    input  wire                    i_ahb_rx_release_pulse,

    output reg                     o_ahb_sw_err_pulse
);

    //--------------------------------------------------------------------------
    // Hang so noi bo
    //--------------------------------------------------------------------------
    localparam [15:0] MAX_PAYLOAD_BYTES_16 = MAX_PAYLOAD_BYTES;
    localparam [ADDR_WIDTH-1:0] LAST_WORD_ADDR = BUFFER_WORDS - 1;

    //--------------------------------------------------------------------------
    // RAM payload ping-pong
    //--------------------------------------------------------------------------
    reg [31:0] r_rx_buf0_mem [0:BUFFER_WORDS-1];
    reg [31:0] r_rx_buf1_mem [0:BUFFER_WORDS-1];

    //--------------------------------------------------------------------------
    // RX clock domain: metadata va fill state
    //--------------------------------------------------------------------------
    reg        r_rx_buf0_valid;

    reg        r_rx_buf1_valid;

    reg        r_rx_fill_active;
    reg        r_rx_fill_buf;
    reg [15:0] r_rx_fill_len;
    reg [9:0]  r_rx_fill_words;

    reg        r_rx_submit_pulse;
    reg        r_rx_submit_busy;
    reg        r_rx_submit_buf_hold;
    reg [15:0] r_rx_submit_len_hold;
    reg [9:0]  r_rx_submit_words_hold;

    wire [9:0] w_fill_need_words =
        r_rx_fill_len[11:2] +
        ((r_rx_fill_len[1:0] != 2'b00) ? 10'd1 : 10'd0);

    wire w_len_valid = (i_rx_frame_len <= MAX_PAYLOAD_BYTES_16);

    wire w_rx_buf0_free = ~r_rx_buf0_valid &
                          ~(r_rx_fill_active & ~r_rx_fill_buf);
    wire w_rx_buf1_free = ~r_rx_buf1_valid &
                          ~(r_rx_fill_active &  r_rx_fill_buf);
    wire w_rx_has_free_buf = w_rx_buf0_free | w_rx_buf1_free;

    wire w_select_fill_buf = w_rx_buf0_free ? 1'b0 : 1'b1;

    wire w_frame_start_accept = i_rx_frame_start &
                                i_rx_en &
                                w_len_valid &
                                ~r_rx_fill_active &
                                ~r_rx_submit_busy &
                                w_rx_has_free_buf;

    wire w_frame_start_busy = i_rx_frame_start &
                              i_rx_en &
                              (r_rx_fill_active |
                               ~w_rx_has_free_buf |
                               r_rx_submit_busy);

    wire w_payload_accept = i_rx_payload_wr_en &
                            r_rx_fill_active &
                            (r_rx_fill_words < w_fill_need_words) &
                            (r_rx_fill_words <= LAST_WORD_ADDR);

    wire w_commit_accept = i_rx_frame_commit &
                           r_rx_fill_active &
                           (r_rx_fill_len <= MAX_PAYLOAD_BYTES_16) &
                           (r_rx_fill_words == w_fill_need_words) &
                           ~r_rx_submit_busy;

    wire w_drop_accept = i_rx_frame_drop & r_rx_fill_active;

    wire w_bad_payload = i_rx_payload_wr_en & ~w_payload_accept;
    wire w_bad_commit  = i_rx_frame_commit & ~w_commit_accept;
    wire w_bad_drop    = i_rx_frame_drop & ~w_drop_accept;

    wire w_payload_write0 = w_payload_accept & ~r_rx_fill_buf;
    wire w_payload_write1 = w_payload_accept &  r_rx_fill_buf;

    wire w_payload_last_word = (i_rx_payload_byte_valid != 2'b00);
    wire [31:0] w_payload_masked = (i_rx_payload_byte_valid == 2'd1) ? {i_rx_payload_wdata[31:24], 24'd0} :
                                   (i_rx_payload_byte_valid == 2'd2) ? {i_rx_payload_wdata[31:16], 16'd0} :
                                   (i_rx_payload_byte_valid == 2'd3) ? {i_rx_payload_wdata[31:8],   8'd0} :
                                                                       i_rx_payload_wdata;

    wire [31:0] w_payload_store = w_payload_last_word ? w_payload_masked :
                                                        i_rx_payload_wdata;

    // Release event tu AHB clock ve RX clock.
    wire w_rx_release0_pulse;
    wire w_rx_release1_pulse;
    wire w_rx_submit_ack_pulse;

    assign o_rx_can_accept = i_rx_en & ~r_rx_fill_active & ~r_rx_submit_busy &
                             w_rx_has_free_buf;

    assign o_rx_pause_req = r_rx_buf0_valid & r_rx_buf1_valid;

    always @(posedge i_rx_clk) begin
        if (w_payload_write0)
            r_rx_buf0_mem[r_rx_fill_words[ADDR_WIDTH-1:0]] <= w_payload_store;
        if (w_payload_write1)
            r_rx_buf1_mem[r_rx_fill_words[ADDR_WIDTH-1:0]] <= w_payload_store;
    end

    always @(posedge i_rx_clk or negedge i_rx_rst_n) begin
        if (!i_rx_rst_n) begin
            r_rx_buf0_valid    <= 1'b0;
            r_rx_buf1_valid    <= 1'b0;
            r_rx_fill_active   <= 1'b0;
            r_rx_fill_buf      <= 1'b0;
            r_rx_fill_len      <= 16'd0;
            r_rx_fill_words    <= 10'd0;
            r_rx_submit_pulse  <= 1'b0;
            r_rx_submit_busy   <= 1'b0;
            r_rx_submit_buf_hold <= 1'b0;
            r_rx_submit_len_hold <= 16'd0;
            r_rx_submit_words_hold <= 10'd0;
            o_rx_busy_pulse    <= 1'b0;
            o_rx_err_pulse     <= 1'b0;
        end else begin
            r_rx_submit_pulse <= 1'b0;
            o_rx_busy_pulse <= w_frame_start_busy;
            o_rx_err_pulse <= w_bad_payload | w_bad_commit | w_bad_drop;

            if (w_rx_submit_ack_pulse)
                r_rx_submit_busy <= 1'b0;

            if (w_rx_release0_pulse)
                r_rx_buf0_valid <= 1'b0;
            if (w_rx_release1_pulse)
                r_rx_buf1_valid <= 1'b0;

            if (w_frame_start_accept) begin
                r_rx_fill_active <= 1'b1;
                r_rx_fill_buf    <= w_select_fill_buf;
                r_rx_fill_len    <= i_rx_frame_len;
                r_rx_fill_words  <= 10'd0;
            end

            if (w_payload_accept)
                r_rx_fill_words <= r_rx_fill_words + 10'd1;

            if (w_drop_accept) begin
                r_rx_fill_active <= 1'b0;
                r_rx_fill_len    <= 16'd0;
                r_rx_fill_words  <= 10'd0;
            end

            if (w_commit_accept) begin
                r_rx_fill_active <= 1'b0;

                if (!r_rx_fill_buf) begin
                    r_rx_buf0_valid <= 1'b1;
                end else begin
                    r_rx_buf1_valid <= 1'b1;
                end

                r_rx_submit_pulse <= 1'b1;
                r_rx_submit_buf_hold <= r_rx_fill_buf;
                r_rx_submit_len_hold <= r_rx_fill_len;
                r_rx_submit_words_hold <= w_fill_need_words;
                r_rx_submit_busy  <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // CDC: submit tu RX sang AHB
    //--------------------------------------------------------------------------
    wire w_ahb_submit_pulse;
    wire [26:0] w_rx_submit_meta = {r_rx_submit_buf_hold,
                                    r_rx_submit_len_hold,
                                    r_rx_submit_words_hold};
    wire [26:0] w_ahb_submit_meta;
    wire        w_ahb_submit_buf;
    wire [15:0] w_ahb_submit_len;
    wire [9:0]  w_ahb_submit_words;

    assign {w_ahb_submit_buf, w_ahb_submit_len,
            w_ahb_submit_words} = w_ahb_submit_meta;

    eth_cdc_pulse u_cdc_submit (
        .i_src_clk   (i_rx_clk),
        .i_src_rst_n (i_rx_rst_n),
        .i_src_pulse (r_rx_submit_pulse),
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .o_dst_pulse (w_ahb_submit_pulse)
    );

    eth_sync_level #(
        .WIDTH       (27),
        .RESET_VALUE (128'd0)
    ) u_sync_submit_meta (
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .i_src_level (w_rx_submit_meta),
        .o_dst_level (w_ahb_submit_meta)
    );

    //--------------------------------------------------------------------------
    // AHB clock domain: queue va doc payload
    //--------------------------------------------------------------------------
    reg        r_ahb_buf0_valid;
    reg [15:0] r_ahb_buf0_len;
    reg [9:0]  r_ahb_buf0_words;

    reg        r_ahb_buf1_valid;
    reg [15:0] r_ahb_buf1_len;
    reg [9:0]  r_ahb_buf1_words;

    reg        r_ahb_q0_valid;
    reg        r_ahb_q0_buf;
    reg        r_ahb_q1_valid;
    reg        r_ahb_q1_buf;
    reg [9:0]  r_ahb_rd_words;
    reg        r_ahb_release0_pulse;
    reg        r_ahb_release1_pulse;
    reg        r_ahb_submit_ack_pulse;

    wire [9:0] w_ahb_q0_words = r_ahb_q0_buf ? r_ahb_buf1_words :
                                                r_ahb_buf0_words;
    wire [15:0] w_ahb_q0_len = r_ahb_q0_buf ? r_ahb_buf1_len :
                                              r_ahb_buf0_len;
    wire w_ahb_read_accept = i_ahb_rx_rd_en &
                             r_ahb_q0_valid &
                             (r_ahb_rd_words < w_ahb_q0_words);
    wire w_ahb_read_bad = i_ahb_rx_rd_en & ~w_ahb_read_accept;
    wire w_ahb_release_accept = i_ahb_rx_release_pulse &
                                r_ahb_q0_valid &
                                (r_ahb_rd_words == w_ahb_q0_words);
    wire w_ahb_release_bad = i_ahb_rx_release_pulse & ~w_ahb_release_accept;

    assign o_ahb_rx_avail = r_ahb_q0_valid;
    assign o_ahb_rx_len   = r_ahb_q0_valid ? w_ahb_q0_len : 16'd0;
    assign o_ahb_rx_words = r_ahb_q0_valid ? w_ahb_q0_words : 10'd0;

    reg r_ahb_q0_valid_next;
    reg r_ahb_q0_buf_next;
    reg r_ahb_q1_valid_next;
    reg r_ahb_q1_buf_next;

    always @(*) begin
        r_ahb_q0_valid_next = r_ahb_q0_valid;
        r_ahb_q0_buf_next   = r_ahb_q0_buf;
        r_ahb_q1_valid_next = r_ahb_q1_valid;
        r_ahb_q1_buf_next   = r_ahb_q1_buf;

        if (w_ahb_release_accept) begin
            r_ahb_q0_valid_next = r_ahb_q1_valid;
            r_ahb_q0_buf_next   = r_ahb_q1_buf;
            r_ahb_q1_valid_next = 1'b0;
            r_ahb_q1_buf_next   = 1'b0;
        end

        if (w_ahb_submit_pulse & ~w_ahb_submit_buf) begin
            if (!r_ahb_q0_valid_next) begin
                r_ahb_q0_valid_next = 1'b1;
                r_ahb_q0_buf_next   = 1'b0;
            end else if (!r_ahb_q1_valid_next) begin
                r_ahb_q1_valid_next = 1'b1;
                r_ahb_q1_buf_next   = 1'b0;
            end
        end

        if (w_ahb_submit_pulse & w_ahb_submit_buf) begin
            if (!r_ahb_q0_valid_next) begin
                r_ahb_q0_valid_next = 1'b1;
                r_ahb_q0_buf_next   = 1'b1;
            end else if (!r_ahb_q1_valid_next) begin
                r_ahb_q1_valid_next = 1'b1;
                r_ahb_q1_buf_next   = 1'b1;
            end
        end
    end

    always @(posedge i_ahb_clk or negedge i_ahb_rst_n) begin
        if (!i_ahb_rst_n) begin
            r_ahb_buf0_valid     <= 1'b0;
            r_ahb_buf0_len       <= 16'd0;
            r_ahb_buf0_words     <= 10'd0;
            r_ahb_buf1_valid     <= 1'b0;
            r_ahb_buf1_len       <= 16'd0;
            r_ahb_buf1_words     <= 10'd0;
            r_ahb_q0_valid       <= 1'b0;
            r_ahb_q0_buf         <= 1'b0;
            r_ahb_q1_valid       <= 1'b0;
            r_ahb_q1_buf         <= 1'b0;
            r_ahb_rd_words       <= 10'd0;
            r_ahb_release0_pulse <= 1'b0;
            r_ahb_release1_pulse <= 1'b0;
            r_ahb_submit_ack_pulse <= 1'b0;
            o_ahb_sw_err_pulse  <= 1'b0;
        end else begin
            r_ahb_q0_valid <= r_ahb_q0_valid_next;
            r_ahb_q0_buf   <= r_ahb_q0_buf_next;
            r_ahb_q1_valid <= r_ahb_q1_valid_next;
            r_ahb_q1_buf   <= r_ahb_q1_buf_next;

            r_ahb_release0_pulse <= 1'b0;
            r_ahb_release1_pulse <= 1'b0;
            r_ahb_submit_ack_pulse <= w_ahb_submit_pulse;
            o_ahb_sw_err_pulse <= w_ahb_read_bad | w_ahb_release_bad;

            if (w_ahb_submit_pulse & ~w_ahb_submit_buf) begin
                r_ahb_buf0_valid <= 1'b1;
                r_ahb_buf0_len   <= w_ahb_submit_len;
                r_ahb_buf0_words <= w_ahb_submit_words;
            end

            if (w_ahb_submit_pulse & w_ahb_submit_buf) begin
                r_ahb_buf1_valid <= 1'b1;
                r_ahb_buf1_len   <= w_ahb_submit_len;
                r_ahb_buf1_words <= w_ahb_submit_words;
            end

            if (w_ahb_read_accept)
                r_ahb_rd_words <= r_ahb_rd_words + 10'd1;

            if (w_ahb_release_accept) begin
                r_ahb_rd_words <= 10'd0;

                if (!r_ahb_q0_buf) begin
                    r_ahb_buf0_valid <= 1'b0;
                    r_ahb_release0_pulse <= 1'b1;
                end else begin
                    r_ahb_buf1_valid <= 1'b0;
                    r_ahb_release1_pulse <= 1'b1;
                end
            end
        end
    end

    wire w_ahb_rd_addr_ok = (r_ahb_rd_words[ADDR_WIDTH-1:0] <= LAST_WORD_ADDR);

    always @(*) begin
        if (w_ahb_read_accept & w_ahb_rd_addr_ok) begin
            if (!r_ahb_q0_buf)
                o_ahb_rx_rdata = r_rx_buf0_mem[r_ahb_rd_words[ADDR_WIDTH-1:0]];
            else
                o_ahb_rx_rdata = r_rx_buf1_mem[r_ahb_rd_words[ADDR_WIDTH-1:0]];
        end else begin
            o_ahb_rx_rdata = 32'd0;
        end
    end

    //--------------------------------------------------------------------------
    // CDC: release/ack tu AHB ve RX
    //--------------------------------------------------------------------------
    eth_cdc_pulse u_cdc_release0 (
        .i_src_clk   (i_ahb_clk),
        .i_src_rst_n (i_ahb_rst_n),
        .i_src_pulse (r_ahb_release0_pulse),
        .i_dst_clk   (i_rx_clk),
        .i_dst_rst_n (i_rx_rst_n),
        .o_dst_pulse (w_rx_release0_pulse)
    );

    eth_cdc_pulse u_cdc_release1 (
        .i_src_clk   (i_ahb_clk),
        .i_src_rst_n (i_ahb_rst_n),
        .i_src_pulse (r_ahb_release1_pulse),
        .i_dst_clk   (i_rx_clk),
        .i_dst_rst_n (i_rx_rst_n),
        .o_dst_pulse (w_rx_release1_pulse)
    );

    eth_cdc_pulse u_cdc_submit_ack (
        .i_src_clk   (i_ahb_clk),
        .i_src_rst_n (i_ahb_rst_n),
        .i_src_pulse (r_ahb_submit_ack_pulse),
        .i_dst_clk   (i_rx_clk),
        .i_dst_rst_n (i_rx_rst_n),
        .o_dst_pulse (w_rx_submit_ack_pulse)
    );

endmodule
