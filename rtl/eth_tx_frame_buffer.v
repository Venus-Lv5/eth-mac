`timescale 1ns/1ps

//------------------------------------------------------------------------------
// TX ping-pong frame buffer
//
// Chuc nang:
// - CPU ghi payload qua TX_DATA trong clock AHB.
// - Payload duoc ghi truc tiep vao buffer RAM noi bo.
// - CPU ghi TX_START de chot buffer hien tai thanh frame cho TX clock doc.
// - TX clock doc lai cung buffer neu can retry half-duplex.
//
// Luu y CDC:
// - Payload RAM co 1 port ghi AHB clock va 1 port doc TX clock.
// - Cac event submit/release/done/err di qua eth_cdc_pulse.
// - Metadata tu AHB sang TX duoc giu on dinh sau submit cho toi khi TX release.
//------------------------------------------------------------------------------
module eth_tx_frame_buffer #(
    parameter MAX_PAYLOAD_BYTES = 1500,
    parameter BUFFER_WORDS      = 375,
    parameter ADDR_WIDTH        = 9
) (
    // AHB/register clock domain.
    input  wire                    i_ahb_clk,
    input  wire                    i_ahb_rst_n,
    input  wire                    i_tx_en,

    input  wire                    i_tx_len_wr_en,
    input  wire [15:0]             i_tx_len,
    input  wire [47:0]             i_tx_da,

    input  wire                    i_tx_payload_wr_en,
    input  wire [31:0]             i_tx_payload_wdata,
    input  wire                    i_tx_start_pulse,

    output wire                    o_ahb_ready,
    output wire                    o_ahb_busy,
    output reg                     o_ahb_sw_err_pulse,
    output wire                    o_ahb_tx_done_pulse,
    output wire                    o_ahb_tx_err_pulse,

    // TX clock domain.
    input  wire                    i_tx_clk,
    input  wire                    i_tx_rst_n,

    output wire                    o_tx_frame_valid,
    output wire [15:0]             o_tx_frame_len,
    output wire [47:0]             o_tx_frame_da,
    output wire [9:0]              o_tx_frame_words,
    output wire                    o_tx_frame_buf,
    input  wire                    i_tx_frame_take,

    output wire                    o_tx_active,
    input  wire [ADDR_WIDTH-1:0]   i_tx_rd_addr,
    input  wire                    i_tx_rd_en,
    output reg  [31:0]             o_tx_rd_data,

    input  wire                    i_tx_done_pulse,
    input  wire                    i_tx_err_pulse
);

    //--------------------------------------------------------------------------
    // Hang so noi bo
    //--------------------------------------------------------------------------
    localparam [15:0] MAX_PAYLOAD_BYTES_16 = MAX_PAYLOAD_BYTES;
    localparam [ADDR_WIDTH-1:0] LAST_WORD_ADDR = BUFFER_WORDS - 1;

    //--------------------------------------------------------------------------
    // RAM payload ping-pong
    //--------------------------------------------------------------------------
    reg [31:0] r_tx_buf0_mem [0:BUFFER_WORDS-1];
    reg [31:0] r_tx_buf1_mem [0:BUFFER_WORDS-1];

    //--------------------------------------------------------------------------
    // AHB clock domain: metadata va fill state
    //--------------------------------------------------------------------------
    reg        r_ahb_buf0_valid;

    reg        r_ahb_buf1_valid;

    reg        r_ahb_fill_active;
    reg        r_ahb_fill_buf;
    reg [15:0] r_ahb_fill_len;
    reg [9:0]  r_ahb_fill_words;

    reg        r_ahb_submit_pulse;
    reg        r_ahb_submit_busy;
    reg        r_ahb_submit_buf_hold;
    reg [15:0] r_ahb_submit_len_hold;
    reg [47:0] r_ahb_submit_da_hold;
    reg [9:0]  r_ahb_submit_words_hold;

    wire [9:0] w_fill_need_words =
        r_ahb_fill_len[11:2] +
        ((r_ahb_fill_len[1:0] != 2'b00) ? 10'd1 : 10'd0);

    wire w_len_valid = (i_tx_len <= MAX_PAYLOAD_BYTES_16);

    wire w_ahb_buf0_free = ~r_ahb_buf0_valid &
                           ~(r_ahb_fill_active & ~r_ahb_fill_buf);
    wire w_ahb_buf1_free = ~r_ahb_buf1_valid &
                           ~(r_ahb_fill_active &  r_ahb_fill_buf);

    wire w_len_accept = i_tx_len_wr_en &
                        i_tx_en &
                        ~r_ahb_fill_active &
                        ~r_ahb_submit_busy &
                        w_len_valid &
                        (w_ahb_buf0_free | w_ahb_buf1_free);

    wire w_select_fill_buf = w_ahb_buf0_free ? 1'b0 : 1'b1;

    wire w_payload_accept = i_tx_payload_wr_en &
                            i_tx_en &
                            r_ahb_fill_active &
                            (w_fill_need_words != 10'd0) &
                            (r_ahb_fill_words < w_fill_need_words);

    wire w_start_accept = i_tx_start_pulse &
                          i_tx_en &
                          r_ahb_fill_active &
                          ~r_ahb_submit_busy &
                          (r_ahb_fill_words == w_fill_need_words);

    wire w_bad_len_wr  = i_tx_len_wr_en & ~w_len_accept;
    wire w_bad_data_wr = i_tx_payload_wr_en & ~w_payload_accept;
    wire w_bad_start   = i_tx_start_pulse & ~w_start_accept;

    wire w_payload_write0 = w_payload_accept & ~r_ahb_fill_buf;
    wire w_payload_write1 = w_payload_accept &  r_ahb_fill_buf;

    // Release event tu TX clock ve AHB clock.
    wire w_ahb_release0_pulse;
    wire w_ahb_release1_pulse;
    wire w_ahb_submit_ack_pulse;

    assign o_ahb_ready = i_tx_en &
                         ~r_ahb_fill_active &
                         ~r_ahb_submit_busy &
                         (w_ahb_buf0_free | w_ahb_buf1_free);

    assign o_ahb_busy = r_ahb_fill_active |
                        r_ahb_submit_busy |
                        r_ahb_buf0_valid |
                        r_ahb_buf1_valid;

    // Port ghi RAM trong AHB clock.
    always @(posedge i_ahb_clk) begin
        if (w_payload_write0)
            r_tx_buf0_mem[r_ahb_fill_words[ADDR_WIDTH-1:0]] <= i_tx_payload_wdata;
        if (w_payload_write1)
            r_tx_buf1_mem[r_ahb_fill_words[ADDR_WIDTH-1:0]] <= i_tx_payload_wdata;
    end

    always @(posedge i_ahb_clk or negedge i_ahb_rst_n) begin
        if (!i_ahb_rst_n) begin
            r_ahb_buf0_valid   <= 1'b0;
            r_ahb_buf1_valid   <= 1'b0;
            r_ahb_fill_active  <= 1'b0;
            r_ahb_fill_buf     <= 1'b0;
            r_ahb_fill_len     <= 16'd0;
            r_ahb_fill_words   <= 10'd0;
            r_ahb_submit_pulse <= 1'b0;
            r_ahb_submit_busy  <= 1'b0;
            r_ahb_submit_buf_hold <= 1'b0;
            r_ahb_submit_len_hold <= 16'd0;
            r_ahb_submit_da_hold <= 48'd0;
            r_ahb_submit_words_hold <= 10'd0;
            o_ahb_sw_err_pulse <= 1'b0;
        end else begin
            r_ahb_submit_pulse <= 1'b0;
            o_ahb_sw_err_pulse <= w_bad_len_wr | w_bad_data_wr | w_bad_start;

            if (w_ahb_submit_ack_pulse)
                r_ahb_submit_busy <= 1'b0;

            if (w_ahb_release0_pulse)
                r_ahb_buf0_valid <= 1'b0;
            if (w_ahb_release1_pulse)
                r_ahb_buf1_valid <= 1'b0;

            if (w_len_accept) begin
                r_ahb_fill_active <= 1'b1;
                r_ahb_fill_buf    <= w_select_fill_buf;
                r_ahb_fill_len    <= i_tx_len;
                r_ahb_fill_words  <= 10'd0;
            end

            if (w_payload_accept)
                r_ahb_fill_words <= r_ahb_fill_words + 10'd1;

            if (w_start_accept) begin
                r_ahb_fill_active <= 1'b0;

                if (!r_ahb_fill_buf) begin
                    r_ahb_buf0_valid <= 1'b1;
                end else begin
                    r_ahb_buf1_valid <= 1'b1;
                end

                r_ahb_submit_pulse <= 1'b1;
                r_ahb_submit_buf_hold <= r_ahb_fill_buf;
                r_ahb_submit_len_hold <= r_ahb_fill_len;
                r_ahb_submit_da_hold <= i_tx_da;
                r_ahb_submit_words_hold <= r_ahb_fill_words;
                r_ahb_submit_busy  <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // CDC: submit tu AHB sang TX
    //--------------------------------------------------------------------------
    wire w_tx_submit_pulse;
    wire [74:0] w_ahb_submit_meta = {r_ahb_submit_buf_hold,
                                     r_ahb_submit_len_hold,
                                     r_ahb_submit_da_hold,
                                     r_ahb_submit_words_hold};
    wire [74:0] w_tx_submit_meta;
    wire        w_tx_submit_buf;
    wire [15:0] w_tx_submit_len;
    wire [47:0] w_tx_submit_da;
    wire [9:0]  w_tx_submit_words;

    assign {w_tx_submit_buf, w_tx_submit_len, w_tx_submit_da,
            w_tx_submit_words} = w_tx_submit_meta;

    eth_cdc_pulse u_cdc_submit (
        .i_src_clk   (i_ahb_clk),
        .i_src_rst_n (i_ahb_rst_n),
        .i_src_pulse (r_ahb_submit_pulse),
        .i_dst_clk   (i_tx_clk),
        .i_dst_rst_n (i_tx_rst_n),
        .o_dst_pulse (w_tx_submit_pulse)
    );

    eth_sync_level #(
        .WIDTH       (75),
        .RESET_VALUE (128'd0)
    ) u_sync_submit_meta (
        .i_dst_clk   (i_tx_clk),
        .i_dst_rst_n (i_tx_rst_n),
        .i_src_level (w_ahb_submit_meta),
        .o_dst_level (w_tx_submit_meta)
    );

    //--------------------------------------------------------------------------
    // TX clock domain: pending/active state
    //--------------------------------------------------------------------------
    reg        r_tx_buf0_valid;
    reg [15:0] r_tx_buf0_len;
    reg [47:0] r_tx_buf0_da;
    reg [9:0]  r_tx_buf0_words;

    reg        r_tx_buf1_valid;
    reg [15:0] r_tx_buf1_len;
    reg [47:0] r_tx_buf1_da;
    reg [9:0]  r_tx_buf1_words;

    reg        r_tx_active;
    reg        r_tx_active_buf;
    reg        r_tx_q0_valid;
    reg        r_tx_q0_buf;
    reg        r_tx_q1_valid;
    reg        r_tx_q1_buf;
    reg        r_tx_release0_pulse;
    reg        r_tx_release1_pulse;
    reg        r_tx_submit_ack_pulse;
    reg        r_tx_done_event;
    reg        r_tx_err_event;

    wire w_tx_take_accept = i_tx_frame_take & ~r_tx_active & r_tx_q0_valid;
    wire w_tx_release = r_tx_active & (i_tx_done_pulse | i_tx_err_pulse);

    assign o_tx_frame_valid = ~r_tx_active & r_tx_q0_valid;
    assign o_tx_frame_buf   = r_tx_q0_buf;
    assign o_tx_frame_len   = o_tx_frame_valid ?
                              (r_tx_q0_buf ? r_tx_buf1_len : r_tx_buf0_len) :
                              16'd0;
    assign o_tx_frame_da    = o_tx_frame_valid ?
                              (r_tx_q0_buf ? r_tx_buf1_da : r_tx_buf0_da) :
                              48'd0;
    assign o_tx_frame_words = o_tx_frame_valid ?
                              (r_tx_q0_buf ? r_tx_buf1_words : r_tx_buf0_words) :
                              10'd0;
    assign o_tx_active = r_tx_active;

    // Hang doi 2 entry giu thu tu submit giua hai buffer.
    reg r_tx_q0_valid_next;
    reg r_tx_q0_buf_next;
    reg r_tx_q1_valid_next;
    reg r_tx_q1_buf_next;

    always @(*) begin
        r_tx_q0_valid_next = r_tx_q0_valid;
        r_tx_q0_buf_next   = r_tx_q0_buf;
        r_tx_q1_valid_next = r_tx_q1_valid;
        r_tx_q1_buf_next   = r_tx_q1_buf;

        if (w_tx_take_accept) begin
            r_tx_q0_valid_next = r_tx_q1_valid;
            r_tx_q0_buf_next   = r_tx_q1_buf;
            r_tx_q1_valid_next = 1'b0;
            r_tx_q1_buf_next   = 1'b0;
        end

        if (w_tx_submit_pulse & ~w_tx_submit_buf) begin
            if (!r_tx_q0_valid_next) begin
                r_tx_q0_valid_next = 1'b1;
                r_tx_q0_buf_next   = 1'b0;
            end else if (!r_tx_q1_valid_next) begin
                r_tx_q1_valid_next = 1'b1;
                r_tx_q1_buf_next   = 1'b0;
            end
        end

        if (w_tx_submit_pulse & w_tx_submit_buf) begin
            if (!r_tx_q0_valid_next) begin
                r_tx_q0_valid_next = 1'b1;
                r_tx_q0_buf_next   = 1'b1;
            end else if (!r_tx_q1_valid_next) begin
                r_tx_q1_valid_next = 1'b1;
                r_tx_q1_buf_next   = 1'b1;
            end
        end
    end

    always @(posedge i_tx_clk or negedge i_tx_rst_n) begin
        if (!i_tx_rst_n) begin
            r_tx_buf0_valid    <= 1'b0;
            r_tx_buf0_len      <= 16'd0;
            r_tx_buf0_da       <= 48'd0;
            r_tx_buf0_words    <= 10'd0;
            r_tx_buf1_valid    <= 1'b0;
            r_tx_buf1_len      <= 16'd0;
            r_tx_buf1_da       <= 48'd0;
            r_tx_buf1_words    <= 10'd0;
            r_tx_active        <= 1'b0;
            r_tx_active_buf    <= 1'b0;
            r_tx_q0_valid      <= 1'b0;
            r_tx_q0_buf        <= 1'b0;
            r_tx_q1_valid      <= 1'b0;
            r_tx_q1_buf        <= 1'b0;
            r_tx_release0_pulse <= 1'b0;
            r_tx_release1_pulse <= 1'b0;
            r_tx_submit_ack_pulse <= 1'b0;
            r_tx_done_event    <= 1'b0;
            r_tx_err_event     <= 1'b0;
        end else begin
            r_tx_q0_valid <= r_tx_q0_valid_next;
            r_tx_q0_buf   <= r_tx_q0_buf_next;
            r_tx_q1_valid <= r_tx_q1_valid_next;
            r_tx_q1_buf   <= r_tx_q1_buf_next;

            r_tx_release0_pulse <= 1'b0;
            r_tx_release1_pulse <= 1'b0;
            r_tx_submit_ack_pulse <= w_tx_submit_pulse;
            r_tx_done_event <= 1'b0;
            r_tx_err_event <= 1'b0;

            if (w_tx_submit_pulse & ~w_tx_submit_buf) begin
                r_tx_buf0_valid <= 1'b1;
                r_tx_buf0_len   <= w_tx_submit_len;
                r_tx_buf0_da    <= w_tx_submit_da;
                r_tx_buf0_words <= w_tx_submit_words;
            end

            if (w_tx_submit_pulse & w_tx_submit_buf) begin
                r_tx_buf1_valid <= 1'b1;
                r_tx_buf1_len   <= w_tx_submit_len;
                r_tx_buf1_da    <= w_tx_submit_da;
                r_tx_buf1_words <= w_tx_submit_words;
            end

            if (w_tx_release) begin
                r_tx_active <= 1'b0;

                if (!r_tx_active_buf) begin
                    r_tx_buf0_valid <= 1'b0;
                    r_tx_release0_pulse <= 1'b1;
                end else begin
                    r_tx_buf1_valid <= 1'b0;
                    r_tx_release1_pulse <= 1'b1;
                end

                if (i_tx_err_pulse)
                    r_tx_err_event <= 1'b1;
                else
                    r_tx_done_event <= 1'b1;
            end else if (w_tx_take_accept) begin
                r_tx_active <= 1'b1;
                r_tx_active_buf <= r_tx_q0_buf;
            end
        end
    end

    // Port doc RAM trong TX clock. Read data co latency 1 chu ky.
    wire w_tx_rd_addr_ok = (i_tx_rd_addr <= LAST_WORD_ADDR);

    always @(posedge i_tx_clk or negedge i_tx_rst_n) begin
        if (!i_tx_rst_n)
            o_tx_rd_data <= 32'd0;
        else if (i_tx_rd_en) begin
            if (!r_tx_active | !w_tx_rd_addr_ok)
                o_tx_rd_data <= 32'd0;
            else if (!r_tx_active_buf)
                o_tx_rd_data <= r_tx_buf0_mem[i_tx_rd_addr];
            else
                o_tx_rd_data <= r_tx_buf1_mem[i_tx_rd_addr];
        end
    end

    //--------------------------------------------------------------------------
    // CDC: release/done/err tu TX ve AHB
    //--------------------------------------------------------------------------
    eth_cdc_pulse u_cdc_release0 (
        .i_src_clk   (i_tx_clk),
        .i_src_rst_n (i_tx_rst_n),
        .i_src_pulse (r_tx_release0_pulse),
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .o_dst_pulse (w_ahb_release0_pulse)
    );

    eth_cdc_pulse u_cdc_release1 (
        .i_src_clk   (i_tx_clk),
        .i_src_rst_n (i_tx_rst_n),
        .i_src_pulse (r_tx_release1_pulse),
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .o_dst_pulse (w_ahb_release1_pulse)
    );

    eth_cdc_pulse u_cdc_submit_ack (
        .i_src_clk   (i_tx_clk),
        .i_src_rst_n (i_tx_rst_n),
        .i_src_pulse (r_tx_submit_ack_pulse),
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .o_dst_pulse (w_ahb_submit_ack_pulse)
    );

    eth_cdc_pulse u_cdc_done (
        .i_src_clk   (i_tx_clk),
        .i_src_rst_n (i_tx_rst_n),
        .i_src_pulse (r_tx_done_event),
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .o_dst_pulse (o_ahb_tx_done_pulse)
    );

    eth_cdc_pulse u_cdc_err (
        .i_src_clk   (i_tx_clk),
        .i_src_rst_n (i_tx_rst_n),
        .i_src_pulse (r_tx_err_event),
        .i_dst_clk   (i_ahb_clk),
        .i_dst_rst_n (i_ahb_rst_n),
        .o_dst_pulse (o_ahb_tx_err_pulse)
    );

endmodule
