`timescale 1ns/1ps

//------------------------------------------------------------------------------
// RX buffer controller
//
// Chuc nang:
// - Nhan byte tu eth_rx_mac trong RX clock.
// - Doc DA/SA/LEN tu 14 byte dau frame.
// - Chi ghi payload that vao eth_rx_frame_buffer.
// - Bo padding, FCS va control frame ra khoi RX frame buffer.
// - Phat RX pause seen khi gap PAUSE frame hop le.
//
// Luu y:
// - Module nay khong tinh CRC. CRC/status do eth_rx_mac dua vao.
// - eth_rx_mac van lam address/hash filter cu cho normal frame.
// - PAUSE/control frame duoc xu ly noi bo, khong dua len CPU.
//------------------------------------------------------------------------------
module eth_rx_buffer_ctrl (
    input  wire        i_clk,
    input  wire        i_rst_n,

    input  wire        i_rx_en,
    input  wire        i_rx_pause_en,
    // Tu eth_rx_mac.
    input  wire        i_rx_valid,
    input  wire [7:0]  i_rx_data,
    input  wire        i_rx_end,
    input  wire        i_rx_abort,
    input  wire        i_crc_err,

    // Sang eth_rx_frame_buffer.
    input  wire        i_buf_can_accept,
    output reg         o_buf_frame_start,
    output reg         o_buf_payload_wr_en,
    output reg  [31:0] o_buf_payload_wdata,
    output reg  [1:0]  o_buf_payload_byte_valid,
    output reg         o_buf_frame_commit,
    output reg         o_buf_frame_drop,
    output reg  [15:0] o_buf_frame_len,

    output reg         o_rx_err_pulse,
    output reg         o_rx_pause_seen_pulse,
    output reg  [15:0] o_rx_pause_time,
    output wire        o_busy
);

    //--------------------------------------------------------------------------
    // Ma trang thai FSM
    //--------------------------------------------------------------------------
    localparam [2:0]
        ST_IDLE    = 3'd0,
        ST_HEADER  = 3'd1,
        ST_PAYLOAD = 3'd2,
        ST_IGNORE  = 3'd3,
        ST_CONTROL = 3'd4,
        ST_DROP    = 3'd5;

    localparam [15:0] MAX_PAYLOAD_BYTES = 16'd1500;
    localparam [15:0] HEADER_BYTES      = 16'd14;
    localparam [47:0] PAUSE_DA          = 48'h0180C2000001;
    localparam [15:0] CTRL_TYPE         = 16'h8808;

    reg [2:0]  r_state;

    //--------------------------------------------------------------------------
    // Thong tin frame dang nhan
    //--------------------------------------------------------------------------
    reg [15:0] r_byte_index;
    reg [15:0] r_frame_len;
    reg [15:0] r_payload_count;
    reg        r_buffer_active;
    reg        r_abort_seen;

    // Header/control detect.
    reg [7:0]  r_type_len_hi;
    reg        r_da_pause_ok;
    reg        r_pause_opcode_ok;
    reg [15:0] r_pause_time;

    // Ghep payload thanh word 32 bit, byte lon truoc.
    reg [31:0] r_word_buf;
    reg [1:0]  r_word_byte_cnt;

    wire [15:0] w_len_from_header = {r_type_len_hi, i_rx_data};
    wire        w_is_ctrl_type = (w_len_from_header == CTRL_TYPE);
    wire        w_len_ok = (w_len_from_header <= MAX_PAYLOAD_BYTES);
    wire        w_payload_last_byte =
                ((r_payload_count + 16'd1) == r_frame_len);
    wire        w_normal_frame_bad =
                r_abort_seen | i_rx_abort | i_crc_err |
                (r_payload_count != r_frame_len);
    wire        w_pause_frame_ok =
                r_da_pause_ok & r_pause_opcode_ok &
                ~r_abort_seen & ~i_rx_abort & ~i_crc_err;

    assign o_busy = (r_state != ST_IDLE);

    //--------------------------------------------------------------------------
    // FSM chinh
    //--------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state <= ST_IDLE;
            r_byte_index <= 16'd0;
            r_frame_len <= 16'd0;
            r_payload_count <= 16'd0;
            r_buffer_active <= 1'b0;
            r_abort_seen <= 1'b0;
            r_type_len_hi <= 8'd0;
            r_da_pause_ok <= 1'b1;
            r_pause_opcode_ok <= 1'b0;
            r_pause_time <= 16'd0;
            r_word_buf <= 32'd0;
            r_word_byte_cnt <= 2'd0;

            o_buf_frame_start <= 1'b0;
            o_buf_payload_wr_en <= 1'b0;
            o_buf_payload_wdata <= 32'd0;
            o_buf_payload_byte_valid <= 2'd0;
            o_buf_frame_commit <= 1'b0;
            o_buf_frame_drop <= 1'b0;
            o_buf_frame_len <= 16'd0;
            o_rx_err_pulse <= 1'b0;
            o_rx_pause_seen_pulse <= 1'b0;
            o_rx_pause_time <= 16'd0;
        end else begin
            o_buf_frame_start <= 1'b0;
            o_buf_payload_wr_en <= 1'b0;
            o_buf_payload_wdata <= 32'd0;
            o_buf_payload_byte_valid <= 2'd0;
            o_buf_frame_commit <= 1'b0;
            o_buf_frame_drop <= 1'b0;
            o_rx_err_pulse <= 1'b0;
            o_rx_pause_seen_pulse <= 1'b0;

            if (i_rx_abort)
                r_abort_seen <= 1'b1;

            if (!i_rx_en) begin
                if (r_buffer_active)
                    o_buf_frame_drop <= 1'b1;
                if (r_state != ST_IDLE)
                    o_rx_err_pulse <= 1'b1;

                r_state <= ST_IDLE;
                r_buffer_active <= 1'b0;
                r_byte_index <= 16'd0;
                r_payload_count <= 16'd0;
                r_word_byte_cnt <= 2'd0;
            end else begin
                case (r_state)
                    ST_IDLE: begin
                        r_buffer_active <= 1'b0;
                        r_byte_index <= 16'd0;
                        r_frame_len <= 16'd0;
                        r_payload_count <= 16'd0;
                        r_abort_seen <= 1'b0;
                        r_type_len_hi <= 8'd0;
                        r_da_pause_ok <= 1'b1;
                        r_pause_opcode_ok <= 1'b0;
                        r_pause_time <= 16'd0;
                        r_word_byte_cnt <= 2'd0;

                        if (i_rx_valid) begin
                            r_da_pause_ok <= (i_rx_data == PAUSE_DA[47:40]);
                            r_byte_index <= 16'd1;
                            r_state <= ST_HEADER;
                        end
                    end

                    ST_HEADER: begin
                        if (i_rx_end) begin
                            o_rx_err_pulse <= 1'b1;
                            r_state <= ST_IDLE;
                        end else if (i_rx_valid) begin
                            case (r_byte_index)
                                16'd1: begin
                                    r_da_pause_ok <= r_da_pause_ok &
                                                     (i_rx_data == PAUSE_DA[39:32]);
                                end
                                16'd2: begin
                                    r_da_pause_ok <= r_da_pause_ok &
                                                     (i_rx_data == PAUSE_DA[31:24]);
                                end
                                16'd3: begin
                                    r_da_pause_ok <= r_da_pause_ok &
                                                     (i_rx_data == PAUSE_DA[23:16]);
                                end
                                16'd4: begin
                                    r_da_pause_ok <= r_da_pause_ok &
                                                     (i_rx_data == PAUSE_DA[15:8]);
                                end
                                16'd5: begin
                                    r_da_pause_ok <= r_da_pause_ok &
                                                     (i_rx_data == PAUSE_DA[7:0]);
                                end
                                16'd12:
                                    r_type_len_hi <= i_rx_data;
                                default:
                                    ;
                            endcase

                            if (r_byte_index == 16'd13) begin
                                if (w_is_ctrl_type) begin
                                    r_byte_index <= HEADER_BYTES;
                                    r_state <= ST_CONTROL;
                                end else if (r_da_pause_ok) begin
                                    r_state <= ST_DROP;
                                end else if (r_abort_seen | i_rx_abort) begin
                                    r_state <= ST_DROP;
                                end else if (w_len_ok) begin
                                    o_buf_frame_start <= 1'b1;
                                    o_buf_frame_len <= w_len_from_header;
                                    r_frame_len <= w_len_from_header;
                                    r_payload_count <= 16'd0;
                                    r_word_byte_cnt <= 2'd0;

                                    if (i_buf_can_accept) begin
                                        r_buffer_active <= 1'b1;
                                        if (w_len_from_header == 16'd0)
                                            r_state <= ST_IGNORE;
                                        else
                                            r_state <= ST_PAYLOAD;
                                    end else begin
                                        r_buffer_active <= 1'b0;
                                        r_state <= ST_DROP;
                                    end
                                end else begin
                                    o_rx_err_pulse <= 1'b1;
                                    r_state <= ST_DROP;
                                end
                            end else begin
                                r_byte_index <= r_byte_index + 16'd1;
                            end
                        end
                    end

                    ST_PAYLOAD: begin
                        if (i_rx_end) begin
                            if (r_buffer_active)
                                o_buf_frame_drop <= 1'b1;
                            o_rx_err_pulse <= 1'b1;
                            r_buffer_active <= 1'b0;
                            r_state <= ST_IDLE;
                        end else if (i_rx_valid) begin
                            case (r_word_byte_cnt)
                                2'd0: begin
                                    r_word_buf[31:24] <= i_rx_data;
                                    if (w_payload_last_byte) begin
                                        o_buf_payload_wr_en <= 1'b1;
                                        o_buf_payload_wdata <= {i_rx_data, 24'd0};
                                        o_buf_payload_byte_valid <= 2'd1;
                                        r_word_byte_cnt <= 2'd0;
                                        r_state <= ST_IGNORE;
                                    end else begin
                                        r_word_byte_cnt <= 2'd1;
                                    end
                                end
                                2'd1: begin
                                    r_word_buf[23:16] <= i_rx_data;
                                    if (w_payload_last_byte) begin
                                        o_buf_payload_wr_en <= 1'b1;
                                        o_buf_payload_wdata <= {r_word_buf[31:24],
                                                                i_rx_data,
                                                                16'd0};
                                        o_buf_payload_byte_valid <= 2'd2;
                                        r_word_byte_cnt <= 2'd0;
                                        r_state <= ST_IGNORE;
                                    end else begin
                                        r_word_byte_cnt <= 2'd2;
                                    end
                                end
                                2'd2: begin
                                    r_word_buf[15:8] <= i_rx_data;
                                    if (w_payload_last_byte) begin
                                        o_buf_payload_wr_en <= 1'b1;
                                        o_buf_payload_wdata <= {r_word_buf[31:16],
                                                                i_rx_data,
                                                                8'd0};
                                        o_buf_payload_byte_valid <= 2'd3;
                                        r_word_byte_cnt <= 2'd0;
                                        r_state <= ST_IGNORE;
                                    end else begin
                                        r_word_byte_cnt <= 2'd3;
                                    end
                                end
                                default: begin
                                    o_buf_payload_wr_en <= 1'b1;
                                    o_buf_payload_wdata <= {r_word_buf[31:8],
                                                            i_rx_data};
                                    o_buf_payload_byte_valid <= 2'd0;
                                    r_word_byte_cnt <= 2'd0;
                                    if (w_payload_last_byte)
                                        r_state <= ST_IGNORE;
                                end
                            endcase

                            r_payload_count <= r_payload_count + 16'd1;
                        end
                    end

                    ST_IGNORE: begin
                        if (i_rx_end) begin
                            if (w_normal_frame_bad) begin
                                if (r_buffer_active)
                                    o_buf_frame_drop <= 1'b1;
                                o_rx_err_pulse <= 1'b1;
                            end else begin
                                o_buf_frame_commit <= r_buffer_active;
                            end

                            r_buffer_active <= 1'b0;
                            r_state <= ST_IDLE;
                        end
                    end

                    ST_CONTROL: begin
                        if (i_rx_end) begin
                            if (i_rx_pause_en & w_pause_frame_ok) begin
                                o_rx_pause_seen_pulse <= 1'b1;
                                o_rx_pause_time <= r_pause_time;
                            end

                            r_state <= ST_IDLE;
                        end else if (i_rx_valid) begin
                            if (r_byte_index == HEADER_BYTES)
                                r_pause_opcode_ok <= (i_rx_data == 8'h00);
                            else if (r_byte_index == (HEADER_BYTES + 16'd1))
                                r_pause_opcode_ok <= r_pause_opcode_ok &
                                                     (i_rx_data == 8'h01);
                            else if (r_byte_index == (HEADER_BYTES + 16'd2))
                                r_pause_time[15:8] <= i_rx_data;
                            else if (r_byte_index == (HEADER_BYTES + 16'd3))
                                r_pause_time[7:0] <= i_rx_data;

                            r_byte_index <= r_byte_index + 16'd1;
                        end
                    end

                    ST_DROP: begin
                        if (i_rx_end)
                            r_state <= ST_IDLE;
                    end

                    default: begin
                        r_state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
