`timescale 1ns/1ps

module eth_tx_dma #(
    localparam integer FifoDepth = 16
)(

    //Global
    input wire                      i_clk,
    input wire                      i_rst_n,

    //BD RAM
    input wire [31:0]               i_db_rdata,

    output reg                      o_db_tx_en,
    output reg                      o_db_db_rd,
    output reg                      o_db_ptr_rd,
    output reg                      o_db_stt_wr,
    output reg                      o_db_wrap,
    output reg [31:0]               o_db_wdata,

    //FIFO
    input wire                      i_fifo_full,
    input wire                      i_fifo_almost_full,
    input wire                      i_fifo_empty,
    input wire                      i_fifo_almost_empty,
    input wire [$clog2(FifoDepth):0] i_fifo_count,

    output reg                      o_fifo_wr,
    output reg                      o_fifo_rd,
    output reg [31:0]               o_fifo_wdata,
    output reg                      o_fifo_clear,

    //AHB master
    input wire                      i_ahb_ack,
    input wire                      i_ahb_err,
    input wire [31:0]              i_ahb_rdata,

    output reg                      o_ahb_req,
    output reg [31:2]               o_ahb_addr,
    output reg [1:0]                o_ahb_addr_lsb,
    output reg [15:0]               o_ahb_len,
    output reg                      o_ahb_burst_en,

    //Register
    input wire                      i_tx_en,

    //MAC
    input wire                      i_mac_clk,
    input wire                      i_mac_used_data,
    input wire                      i_mac_retry,
    input wire                      i_mac_abort,
    input wire                      i_mac_done,
    input wire                      i_mac_defer,
    input wire                      i_mac_retry_lmt,
    input wire                      i_mac_late_coll,
    input wire                      i_mac_carry_lost,
    input wire [3:0]                i_mac_retry_cnt,

    output reg                      o_mac_start,
    output reg                      o_mac_end,

    output reg                      o_mac_crc,
    output reg                      o_mac_pad,
    output reg                      o_mac_underrun,

    //Interrupt
    output reg                      o_irq_done,
    output reg                      o_irq_err
);

    //===========================================================
    // CDC tu MAC sang DMA (MTxClk -> i_clk)
    //===========================================================

    // retry
    reg                             r_mac_retry_sync1;
    reg                             r_mac_retry_sync2;
    reg                             r_mac_retry_d;

    // abort
    reg                             r_mac_abort_sync1;
    reg                             r_mac_abort_sync2;
    reg                             r_mac_abort_d;

    // done
    reg                             r_mac_done_sync1;
    reg                             r_mac_done_sync2;
    reg                             r_mac_done_d;

    // defer
    reg                             r_mac_defer_sync1;
    reg                             r_mac_defer_sync2;

    // used data
    reg                             r_mac_used_data_sync1;
    reg                             r_mac_used_data_sync2;
    reg                             r_mac_used_data_d;

    // retry limit
    reg                             r_mac_retry_lmt_sync1;
    reg                             r_mac_retry_lmt_sync2;

    // late collision
    reg                             r_mac_late_coll_sync1;
    reg                             r_mac_late_coll_sync2;

    // carrier lost
    reg                             r_mac_carry_lost_sync1;
    reg                             r_mac_carry_lost_sync2;

    // retry counter (4 bits)
    reg [3:0]                       r_mac_retry_cnt_sync1;
    reg [3:0]                       r_mac_retry_cnt_sync2;
    reg [3:0]                       r_mac_retry_cnt_d;

    //===========================================================
    // CDC tu DMA sang MAC (i_clk -> MTxClk)
    //===========================================================

    // start frame
    reg                             r_mac_start_sync1;
    reg                             r_mac_start_sync2;
    reg                             r_mac_start_syncb1;
    reg                             r_mac_start_syncb2;

    // end frame
    reg                             r_mac_end_sync1;
    reg                             r_mac_end_sync2;
    reg                             r_mac_end_syncb1;
    reg                             r_mac_end_syncb2;

    //===========================================================
    // CDC retry: 2FF + delay register
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_retry_sync1 <= 1'b0;
            r_mac_retry_sync2 <= 1'b0;
            r_mac_retry_d <= 1'b0;
        end else begin
            r_mac_retry_sync1 <= i_mac_retry;
            r_mac_retry_sync2 <= r_mac_retry_sync1;
            r_mac_retry_d <= r_mac_retry_sync2;
        end
    end

    wire                            w_mac_retry_pulse;
    assign w_mac_retry_pulse = r_mac_retry_sync2 & ~r_mac_retry_d;

    //===========================================================
    // CDC abort: 2FF + delay register
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_abort_sync1 <= 1'b0;
            r_mac_abort_sync2 <= 1'b0;
            r_mac_abort_d <= 1'b0;
        end else begin
            r_mac_abort_sync1 <= i_mac_abort;
            r_mac_abort_sync2 <= r_mac_abort_sync1;
            r_mac_abort_d <= r_mac_abort_sync2;
        end
    end

    wire                            w_mac_abort_pulse;
    assign w_mac_abort_pulse = r_mac_abort_sync2 & ~r_mac_abort_d;

    //===========================================================
    // CDC done: 2FF + delay register
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_done_sync1 <= 1'b0;
            r_mac_done_sync2 <= 1'b0;
            r_mac_done_d <= 1'b0;
        end else begin
            r_mac_done_sync1 <= i_mac_done;
            r_mac_done_sync2 <= r_mac_done_sync1;
            r_mac_done_d <= r_mac_done_sync2;
        end
    end

    wire                            w_mac_done_pulse;
    assign w_mac_done_pulse = r_mac_done_sync2 & ~r_mac_done_d;

    // Pulse aliases for BD and FIFO control
    wire                            w_abort_pulse;
    wire                            w_retry_pulse;
    wire                            w_done_pulse;
    assign w_abort_pulse = w_mac_abort_pulse;
    assign w_retry_pulse = w_mac_retry_pulse;
    assign w_done_pulse  = w_mac_done_pulse;

    //===========================================================
    // CDC defer: 2FF
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_defer_sync1 <= 1'b0;
            r_mac_defer_sync2 <= 1'b0;
        end else begin
            r_mac_defer_sync1 <= i_mac_defer;
            r_mac_defer_sync2 <= r_mac_defer_sync1;
        end
    end

    wire                            w_mac_defer;
    assign w_mac_defer = r_mac_defer_sync2;

    //===========================================================
    // CDC used data: 2FF + delay register
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_used_data_sync1 <= 1'b0;
            r_mac_used_data_sync2 <= 1'b0;
            r_mac_used_data_d <= 1'b0;
        end else begin
            r_mac_used_data_sync1 <= i_mac_used_data;
            r_mac_used_data_sync2 <= r_mac_used_data_sync1;
            r_mac_used_data_d <= r_mac_used_data_sync2;
        end
    end

    wire                            w_mac_used_data;
    assign w_mac_used_data = r_mac_used_data_sync2;

    //===========================================================
    // CDC retry limit: 2FF
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_retry_lmt_sync1 <= 1'b0;
            r_mac_retry_lmt_sync2 <= 1'b0;
        end else begin
            r_mac_retry_lmt_sync1 <= i_mac_retry_lmt;
            r_mac_retry_lmt_sync2 <= r_mac_retry_lmt_sync1;
        end
    end

    //===========================================================
    // CDC late collision: 2FF
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_late_coll_sync1 <= 1'b0;
            r_mac_late_coll_sync2 <= 1'b0;
        end else begin
            r_mac_late_coll_sync1 <= i_mac_late_coll;
            r_mac_late_coll_sync2 <= r_mac_late_coll_sync1;
        end
    end

    //===========================================================
    // CDC carrier lost: 2FF
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_carry_lost_sync1 <= 1'b0;
            r_mac_carry_lost_sync2 <= 1'b0;
        end else begin
            r_mac_carry_lost_sync1 <= i_mac_carry_lost;
            r_mac_carry_lost_sync2 <= r_mac_carry_lost_sync1;
        end
    end

    //===========================================================
    // CDC retry counter: 2FF + delay register (4 bits)
    //===========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_retry_cnt_sync1 <= 4'h0;
            r_mac_retry_cnt_sync2 <= 4'h0;
            r_mac_retry_cnt_d <= 4'h0;
        end else begin
            r_mac_retry_cnt_sync1 <= i_mac_retry_cnt;
            r_mac_retry_cnt_sync2 <= r_mac_retry_cnt_sync1;
            r_mac_retry_cnt_d <= r_mac_retry_cnt_sync2;
        end
    end

    wire [3:0]                      w_mac_retry_cnt;
    assign w_mac_retry_cnt = r_mac_retry_cnt_sync2;

    //===========================================================
    // CDC start frame: 2FF (MAC clk) + 2FF (feedback)
    //===========================================================
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_start_sync1 <= 1'b0;
            r_mac_start_sync2 <= 1'b0;
        end else begin
            r_mac_start_sync1 <= o_mac_start;
            r_mac_start_sync2 <= r_mac_start_sync1;
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_start_syncb1 <= 1'b0;
            r_mac_start_syncb2 <= 1'b0;
        end else begin
            r_mac_start_syncb1 <= r_mac_start_sync2;
            r_mac_start_syncb2 <= r_mac_start_syncb1;
        end
    end

    //===========================================================
    // CDC end frame: 2FF (MAC clk) + 2FF (feedback)
    //===========================================================
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_end_sync1 <= 1'b0;
            r_mac_end_sync2 <= 1'b0;
        end else begin
            r_mac_end_sync1 <= o_mac_end;
            r_mac_end_sync2 <= r_mac_end_sync1;
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_end_syncb1 <= 1'b0;
            r_mac_end_syncb2 <= 1'b0;
        end else begin
            r_mac_end_syncb1 <= r_mac_end_sync2;
            r_mac_end_syncb2 <= r_mac_end_syncb1;
        end
    end

    //===========================================================
    // TX BD Controller
    //===========================================================

    // TX enable
    reg r_tx_en_q;
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_tx_en_q <= 1'b0;
        else r_tx_en_q <= i_tx_en;

    reg r_tx_en;
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_tx_en <= 1'b0;
        else r_tx_en <= r_tx_en_q;

    // TX BD address
    reg [6:0] r_bd_addr;
    wire w_wrap;
    wire w_irq_en;

    wire [6:0] w_next_bd = w_wrap ? 7'h0 : (r_bd_addr + 1'b1);

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_bd_addr <= 7'h0;
        else if (i_tx_en && ~r_tx_en) r_bd_addr <= 7'h0;
        else if (w_stt_wr) r_bd_addr <= w_next_bd;

    // TX BD ready
    reg r_bd_rdy;
    wire w_rst_bd_rdy = w_retry_pulse | w_abort_pulse | w_done_pulse;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_bd_rdy <= 1'b0;
        else if (r_tx_en && r_tx_en_q && r_bd_rd)
            r_bd_rdy <= i_db_rdata[15] & (i_db_rdata[31:16] > 16'd4);
        else if (w_rst_bd_rdy) r_bd_rdy <= 1'b0;

    // TX BD read
    reg r_bd_rd;
    reg r_blk_bd_rd;
    wire w_st_bd_rd = (r_retry_pkt | w_stt_wr) & ~r_blk_bd_rd & ~r_bd_rdy;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_bd_rd <= 1'b1;
        else if (w_st_bd_rd) r_bd_rd <= 1'b1;
        else if (r_bd_rdy) r_bd_rd <= 1'b0;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_blk_bd_rd <= 1'b0;
        else if (w_st_bd_rd) r_blk_bd_rd <= 1'b1;
        else if (~w_st_bd_rd && ~r_bd_rdy) r_blk_bd_rd <= 1'b0;

    // TX pointer read
    reg r_ptr_rd;
    wire w_st_ptr_rd = r_bd_rd & r_bd_rdy;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_rd <= 1'b0;
        else if (w_st_ptr_rd) r_ptr_rd <= 1'b1;
        else if (r_tx_en && r_tx_en_q) r_ptr_rd <= 1'b0;

    // TX status from BD
    reg [3:0] r_stt;
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_stt <= 4'h0;
        else if (r_tx_en && r_tx_en_q && r_bd_rd) r_stt <= i_db_rdata[14:11];

    assign w_irq_en = r_stt[3];
    assign w_wrap = r_stt[2];
    assign o_mac_pad = r_stt[1];
    assign o_mac_crc = r_stt[0];

    // TX length
    reg [15:0] r_len;
    reg [15:0] r_len_lat;
    wire w_len_eq0 = (r_len == 16'h0);
    wire w_len_lt4 = (r_len < 16'd4);

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_len <= 16'h0;
        else if (r_tx_en && r_tx_en_q && r_bd_rd) r_len <= i_db_rdata[31:16];
        else if (r_ahb_tx && i_ahb_ack) begin
            if (w_len_lt4) r_len <= 16'h0;
            else if (r_ptr_lsb_rst == 2'b00) r_len <= r_len - 16'd4;
            else if (r_ptr_lsb_rst == 2'b01) r_len <= r_len - 16'd3;
            else if (r_ptr_lsb_rst == 2'b10) r_len <= r_len - 16'd2;
            else r_len <= r_len - 16'd1;
        end

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_len_lat <= 16'h0;
        else if (r_tx_en && r_tx_en_q && r_bd_rd) r_len_lat <= i_db_rdata[31:16];

    // TX pointer
    reg [31:2] r_ptr_msb;
    reg [1:0] r_ptr_lsb;
    reg [1:0] r_ptr_lsb_rst;
    reg r_blk_ptr;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_msb <= 30'h0;
        else if (r_tx_en && r_tx_en_q && r_ptr_rd) r_ptr_msb <= i_db_rdata[31:2];
        else if (r_incr_ptr && ~r_blk_ptr) r_ptr_msb <= r_ptr_msb + 1'b1;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_lsb <= 2'b0;
        else if (r_tx_en && r_tx_en_q && r_ptr_rd) r_ptr_lsb <= i_db_rdata[1:0];

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_lsb_rst <= 2'b0;
        else if (r_tx_en && r_tx_en_q && r_ptr_rd) r_ptr_lsb_rst <= i_db_rdata[1:0];
        else if (r_ahb_tx && i_ahb_ack) r_ptr_lsb_rst <= 2'b0;

    // TX status write
    reg r_stt_wr;
    reg r_blk_stt_wr;
    wire w_stt_wr = (r_done_pkt | r_abort_pkt) & r_tx_en & r_tx_en_q & ~r_blk_stt_wr;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_blk_stt_wr <= 1'b0;
        else if (~r_done_s && ~r_abort_s) r_blk_stt_wr <= 1'b0;
        else if (w_stt_wr) r_blk_stt_wr <= 1'b1;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_stt_wr <= 1'b0;
        else r_stt_wr <= w_stt_wr;

    // Status data for BD write
    wire [8:0] w_stt_in = {
        w_mac_under_run,
        w_mac_retry_cnt,
        r_mac_retry_lmt_sync2,
        r_mac_late_coll_sync2,
        r_mac_defer_sync2,
        r_mac_carry_lost_sync2
    };
    wire [31:0] w_bd_din = {r_len_lat, 1'b0, r_stt, 2'b0, w_stt_in};

    // BD RAM control outputs
    always @(*) begin
        o_db_tx_en = 1'b1;
        o_db_db_rd = r_bd_rd;
        o_db_ptr_rd = r_ptr_rd;
        o_db_stt_wr = r_stt_wr;
        o_db_wrap = w_wrap;
        o_db_wdata = w_bd_din;
    end

    wire [7:0] w_bd_addr = {1'b0, r_bd_addr};

    //===========================================================
    // Packet flags
    //===========================================================
    reg r_done_pkt;
    reg r_abort_pkt;
    reg r_retry_pkt;
    reg r_done_s;
    reg r_abort_s;

    //===========================================================
    // AHB Master TX
    //===========================================================

    // Read Memory Request
    // Set when: TX enable + BD ready + Pointer read done
    // Clear when: length=0 OR abort pulse OR retry pulse
    wire w_set_rd_mem = r_tx_en && r_bd_rdy && r_ptr_rd;

    reg r_rd_mem;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rd_mem <= 1'b0;
        else if (w_len_eq0 || w_abort_pulse || w_retry_pulse)
            r_rd_mem <= 1'b0;
        else if (w_set_rd_mem)
            r_rd_mem <= 1'b1;
    end

    // Block Read when FIFO almost full OR remaining len <= 4
    reg r_blk_rd_mem;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_blk_rd_mem <= 1'b0;
        else if ((i_fifo_almost_full || (r_len <= 16'd4)) && r_ahb_tx && ~r_blk_rd_mem)
            r_blk_rd_mem <= 1'b1;
        else if (~i_fifo_almost_full && r_ahb_tx && ~r_blk_rd_mem)
            r_blk_rd_mem <= 1'b0;
    end

    // Actual read enable (request AND not blocked)
    wire w_rd_mem_active = r_rd_mem && ~r_blk_rd_mem;

    // Burst enable: remaining > BURST_LENGTH*4 + 4
    // Using 5 for ETH_BURST_LENGTH=1 (minimal burst)
    wire w_tx_burst_en = (r_len > 16'd8) && ~i_fifo_almost_full;

    // AHB TX active flag
    reg r_ahb_tx;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_ahb_tx <= 1'b0;
        else if (w_set_rd_mem)
            r_ahb_tx <= 1'b1;
        else if (w_len_eq0 && i_ahb_ack)
            r_ahb_tx <= 1'b0;
    end

    // AHB request output
    reg r_ahb_req;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_ahb_req <= 1'b0;
        else if (w_set_rd_mem)
            r_ahb_req <= 1'b1;
        else if (w_len_eq0 && i_ahb_ack)
            r_ahb_req <= 1'b0;
    end

    // Burst counter
    reg [3:0] r_tx_burst_cnt;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_burst_cnt <= 4'h0;
        else if (w_set_rd_mem)
            r_tx_burst_cnt <= 4'h0;
        else if (r_ahb_tx && i_ahb_ack && w_tx_burst_en)
            r_tx_burst_cnt <= r_tx_burst_cnt + 4'h1;
    end

    // TX pointer increment on AHB ack
    reg r_incr_ptr;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_incr_ptr <= 1'b0;
        else if (r_ahb_tx && i_ahb_ack && ~w_len_eq0)
            r_incr_ptr <= 1'b1;
        else
            r_incr_ptr <= 1'b0;
    end

    // Block pointer increment to prevent double increment
    reg r_blk_ptr;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_blk_ptr <= 1'b0;
        else if (i_ahb_ack)
            r_blk_ptr <= 1'b1;
        else
            r_blk_ptr <= 1'b0;
    end

    // AHB address MSB (word-aligned)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_ahb_addr <= 30'h0;
        else if (w_set_rd_mem)
            o_ahb_addr <= r_ptr_msb;
    end

    // AHB address LSB (byte offset)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_ahb_addr_lsb <= 2'b0;
        else if (w_set_rd_mem)
            o_ahb_addr_lsb <= r_ptr_lsb_rst;
    end

    // AHB length (remaining bytes)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_ahb_len <= 16'h0;
        else if (w_set_rd_mem)
            o_ahb_len <= r_len;
    end

    // AHB burst enable
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_ahb_burst_en <= 1'b0;
        else if (w_set_rd_mem)
            o_ahb_burst_en <= w_tx_burst_en;
    end

    // Output assignment
    assign o_ahb_req = r_ahb_req;

    //===========================================================
    // FIFO Controller
    // Reference: eth_wishbone.v (line 1308-1402)
    //===========================================================

    // FIFO Write: When AHB TX transfer complete (ack received)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_fifo_wr <= 1'b0;
        else
            o_fifo_wr <= r_ahb_tx && i_ahb_ack;
    end

    // FIFO data input from AHB
    always @(posedge i_clk) begin
        o_fifo_wdata <= i_ahb_rdata;
    end

    // FIFO Read: When MAC needs data (used_data) and FIFO not empty
    wire w_fifo_read = w_mac_used_data && ~i_fifo_empty;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_fifo_rd <= 1'b0;
        else
            o_fifo_rd <= w_fifo_read;
    end

    // FIFO Clear: On abort or retry pulse
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_fifo_clear <= 1'b0;
        else
            o_fifo_clear <= w_abort_pulse || w_retry_pulse;
    end

    //===========================================================
    // MAC Frame Control
    //===========================================================

    // TX Underrun Generation
    // Underrun when: FIFO empty AND MAC is consuming data (used_data=1)
    // This is synchronized to i_mac_clk for output
    reg                             r_mac_underrun_wb;

    // Underrun flag in i_clk domain
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_underrun_wb <= 1'b0;
        else if (w_abort_pulse)
            r_mac_underrun_wb <= 1'b0;
        else if (i_fifo_empty && w_mac_used_data)
            r_mac_underrun_wb <= 1'b1;
    end

    // CDC to i_mac_clk
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_underrun_sync1 <= 1'b0;
            r_mac_underrun_sync2 <= 1'b0;
        end else begin
            r_mac_underrun_sync1 <= r_mac_underrun_wb;
            r_mac_underrun_sync2 <= r_mac_underrun_sync1;
        end
    end

    // Latched underrun output (cleared when status write completes)
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_mac_underrun <= 1'b0;
        else if (r_mac_start_syncb2)  // Status write complete
            o_mac_underrun <= 1'b0;
        else if (r_mac_underrun_sync2)
            o_mac_underrun <= 1'b1;
    end

    // Start Frame: When BD ready AND (FIFO full OR length=0) AND not started yet
    reg r_start_occured;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_start_occured <= 1'b0;
        else if (o_mac_start)
            r_start_occured <= 1'b1;
        else if (w_done_pulse || w_abort_pulse || w_retry_pulse)
            r_start_occured <= 1'b0;
    end

    wire w_start_frame = r_bd_rdy &&
                        ~r_start_occured &&
                        (i_fifo_full || w_len_eq0);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_mac_start <= 1'b0;
        else
            o_mac_start <= w_start_frame;
    end

    // End Frame: When length=0 AND FIFO almost empty AND MAC consuming data
    wire w_end_frame = w_len_eq0 && i_fifo_almost_empty && w_mac_used_data;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_mac_end <= 1'b0;
        else
            o_mac_end <= w_end_frame;
    end

    //===========================================================
    // MAC Interface Handler
    //===========================================================
    // Reference: eth_wishbone.v lines 455-1671

    // Packet flags (latched until status write)
    reg                             r_done_pkt;
    reg                             r_abort_pkt;
    reg                             r_retry_pkt;

    // Blocked flags (prevent re-triggering)
    reg                             r_done_pkt_blocked;
    reg                             r_abort_pkt_blocked;
    reg                             r_retry_pkt_blocked;

    // Done packet: set on done pulse, cleared when status write starts
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_done_pkt <= 1'b0;
        else if (w_done_pulse && !r_done_pkt_blocked)
            r_done_pkt <= 1'b1;
        else if (r_stt_wr)
            r_done_pkt <= 1'b0;
    end

    // Abort packet: set on abort pulse, cleared when status write starts
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_abort_pkt <= 1'b0;
        else if (w_abort_pulse && !r_abort_pkt_blocked)
            r_abort_pkt <= 1'b1;
        else if (r_stt_wr)
            r_abort_pkt <= 1'b0;
    end

    // Retry packet: set on retry pulse, cleared when BD read starts
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_retry_pkt <= 1'b0;
        else if (w_retry_pulse && !r_retry_pkt_blocked)
            r_retry_pkt <= 1'b1;
        else if (r_bd_rd)
            r_retry_pkt <= 1'b0;
    end

    // Block done packet when set, unblock when done goes low
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_done_pkt_blocked <= 1'b0;
        else if (~w_mac_done && r_mac_done_d)
            r_done_pkt_blocked <= 1'b0;
        else if (r_done_pkt)
            r_done_pkt_blocked <= 1'b1;
    end

    // Block abort packet when set, unblock when abort goes low
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_abort_pkt_blocked <= 1'b0;
        else if (~w_mac_abort && r_mac_abort_d)
            r_abort_pkt_blocked <= 1'b0;
        else if (r_abort_pkt)
            r_abort_pkt_blocked <= 1'b1;
    end

    // Block retry packet when set, unblock when retry goes low
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_retry_pkt_blocked <= 1'b0;
        else if (~w_mac_retry && r_mac_retry_d)
            r_retry_pkt_blocked <= 1'b0;
        else if (r_retry_pkt)
            r_retry_pkt_blocked <= 1'b1;
    end

    // Error status from MAC
    wire                            w_tx_error;
    assign w_tx_error = r_mac_underrun_wb            |  // Underrun (internal signal)
                        r_mac_retry_lmt_sync2     |  // Retry limit reached
                        r_mac_late_coll_sync2     |  // Late collision
                        r_mac_carry_lost_sync2;      // Carry lost

    // Interrupt: Done - set on done packet, cleared by CPU or reset
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_irq_done <= 1'b0;
        else if (r_done_pkt)
            o_irq_done <= 1'b1;
        else
            o_irq_done <= 1'b0;
    end

    // Interrupt: Error - set on abort packet or TX error
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_irq_err <= 1'b0;
        else if (r_abort_pkt || w_tx_error)
            o_irq_err <= 1'b1;
        else
            o_irq_err <= 1'b0;
    end

endmodule
