`timescale 1ns/1ps

module eth_rx_dma #(
    localparam integer FifoDepth = 16
)(

    //Global
    input wire                      i_clk,
    input wire                      i_rst_n,

    //BD RAM
    input wire [31:0]               i_db_rdata,

    output reg                      o_db_rx_en,
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
    input wire [31:0]               i_fifo_rdata,

    output reg                      o_fifo_wr,
    output reg                      o_fifo_rd,
    output reg [31:0]               o_fifo_wdata,
    output reg                      o_fifo_clear,

    //AHB master
    input wire                      i_ahb_ack,
    input wire                      i_ahb_err,
    input wire [31:0]               i_ahb_rdata,

    output reg                      o_ahb_req,
    output reg [31:2]               o_ahb_addr,
    output reg [1:0]                o_ahb_addr_lsb,
    output reg [15:0]               o_ahb_len,
    output reg                      o_ahb_burst_en,

    //Register
    input wire                      i_rx_en,

    //MAC (MRxClk domain)
    input wire                      i_mac_clk,
    input wire                      i_mac_rx_valid,
    input wire                      i_mac_rx_start_frm,
    input wire                      i_mac_rx_end_frm,
    input wire                      i_mac_rx_abort,
    input wire [7:0]                i_mac_rx_data,
    input wire [1:0]                i_mac_rx_byte_cnt,

    //Interrupt
    output reg                      o_irq_done,
    output reg                      o_irq_err
);

    //===========================================================
    // RX BD Status bits (from Specification)
    //===========================================================
    // Word 0: [31:16] LEN, [15:11] Rsvd, [10] CF, [9] M, [8] OR,
    //         [7] IS, [6] TL, [5] SF, [4] CRC, [3] LC, [2] E, [1] IRQ, [0] WR

    localparam [4:0] BD_BIT_WR   = 5'd0;  // Wrap
    localparam [4:0] BD_BIT_IRQ  = 5'd1;  // Interrupt Enable
    localparam [4:0] BD_BIT_E    = 5'd2;  // Empty (Ready for receive)
    localparam [4:0] BD_BIT_LC   = 5'd3;  // Late Collision
    localparam [4:0] BD_BIT_CRC  = 5'd4;  // CRC Error
    localparam [4:0] BD_BIT_SF   = 5'd5;  // Short Frame
    localparam [4:0] BD_BIT_TL   = 5'd6;  // Too Long
    localparam [4:0] BD_BIT_IS   = 5'd7;  // Invalid Symbol
    localparam [4:0] BD_BIT_OR   = 5'd8;  // Overrun
    localparam [4:0] BD_BIT_M    = 5'd9;  // Miss (promiscuous)
    localparam [4:0] BD_BIT_CF   = 5'd10; // Control Frame

    //===========================================================
    // CDC tu MAC sang DMA (MRxClk -> i_clk)
    //===========================================================

    // rx_valid: 2FF + delay
    reg                             r_mac_rx_valid_sync1;
    reg                             r_mac_rx_valid_sync2;
    reg                             r_mac_rx_valid_d;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_rx_valid_sync1 <= 1'b0;
            r_mac_rx_valid_sync2 <= 1'b0;
            r_mac_rx_valid_d <= 1'b0;
        end else begin
            r_mac_rx_valid_sync1 <= i_mac_rx_valid;
            r_mac_rx_valid_sync2 <= r_mac_rx_valid_sync1;
            r_mac_rx_valid_d <= r_mac_rx_valid_sync2;
        end
    end

    wire                            w_mac_rx_valid;
    assign w_mac_rx_valid = r_mac_rx_valid_sync2;

    // rx_start_frm: 2FF + delay
    reg                             r_mac_rx_start_sync1;
    reg                             r_mac_rx_start_sync2;
    reg                             r_mac_rx_start_d;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_rx_start_sync1 <= 1'b0;
            r_mac_rx_start_sync2 <= 1'b0;
            r_mac_rx_start_d <= 1'b0;
        end else begin
            r_mac_rx_start_sync1 <= i_mac_rx_start_frm;
            r_mac_rx_start_sync2 <= r_mac_rx_start_sync1;
            r_mac_rx_start_d <= r_mac_rx_start_sync2;
        end
    end

    wire                            w_mac_rx_start;
    assign w_mac_rx_start = r_mac_rx_start_sync2;

    // rx_end_frm: 2FF + delay
    reg                             r_mac_rx_end_sync1;
    reg                             r_mac_rx_end_sync2;
    reg                             r_mac_rx_end_d;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_rx_end_sync1 <= 1'b0;
            r_mac_rx_end_sync2 <= 1'b0;
            r_mac_rx_end_d <= 1'b0;
        end else begin
            r_mac_rx_end_sync1 <= i_mac_rx_end_frm;
            r_mac_rx_end_sync2 <= r_mac_rx_end_sync1;
            r_mac_rx_end_d <= r_mac_rx_end_sync2;
        end
    end

    wire                            w_mac_rx_end;
    assign w_mac_rx_end = r_mac_rx_end_sync2;

    // rx_abort: 2FF + delay
    reg                             r_mac_rx_abort_sync1;
    reg                             r_mac_rx_abort_sync2;
    reg                             r_mac_rx_abort_d;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_rx_abort_sync1 <= 1'b0;
            r_mac_rx_abort_sync2 <= 1'b0;
            r_mac_rx_abort_d <= 1'b0;
        end else begin
            r_mac_rx_abort_sync1 <= i_mac_rx_abort;
            r_mac_rx_abort_sync2 <= r_mac_rx_abort_sync1;
            r_mac_rx_abort_d <= r_mac_rx_abort_sync2;
        end
    end

    wire                            w_mac_rx_abort;
    assign w_mac_rx_abort = r_mac_rx_abort_sync2;

    // rx_data: 2FF pipeline
    reg [7:0]                       r_mac_rx_data_sync1;
    reg [7:0]                       r_mac_rx_data_sync2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_rx_data_sync1 <= 8'h0;
            r_mac_rx_data_sync2 <= 8'h0;
        end else begin
            r_mac_rx_data_sync1 <= i_mac_rx_data;
            r_mac_rx_data_sync2 <= r_mac_rx_data_sync1;
        end
    end

    wire [7:0]                      w_mac_rx_data;
    assign w_mac_rx_data = r_mac_rx_data_sync2;

    // rx_byte_cnt: 2FF pipeline
    reg [1:0]                       r_mac_rx_byte_cnt_sync1;
    reg [1:0]                       r_mac_rx_byte_cnt_sync2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mac_rx_byte_cnt_sync1 <= 2'h0;
            r_mac_rx_byte_cnt_sync2 <= 2'h0;
        end else begin
            r_mac_rx_byte_cnt_sync1 <= i_mac_rx_byte_cnt;
            r_mac_rx_byte_cnt_sync2 <= r_mac_rx_byte_cnt_sync1;
        end
    end

    wire [1:0]                      w_mac_rx_byte_cnt;
    assign w_mac_rx_byte_cnt = r_mac_rx_byte_cnt_sync2;

    //===========================================================
    // RX Enable (delayed, same as TX)
    //===========================================================
    reg                             r_rx_en_q;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_rx_en_q <= 1'b0;
        else r_rx_en_q <= i_rx_en;

    reg                             r_rx_en;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_rx_en <= 1'b0;
        else r_rx_en <= r_rx_en_q;

    //===========================================================
    // RX BD Controller
    //===========================================================

    // RX BD address
    reg [6:0]                       r_bd_addr;
    wire [6:0]                      w_next_bd;
    wire                            w_wrap;

    assign w_next_bd = w_wrap ? 7'h0 : (r_bd_addr + 1'b1);

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_bd_addr <= 7'h0;
        else if (i_rx_en && ~r_rx_en) r_bd_addr <= 7'h0;
        else if (w_stt_wr) r_bd_addr <= w_next_bd;

    // RX BD ready
    reg                             r_bd_rdy;
    wire                            w_rst_bd_rdy;

    assign w_rst_bd_rdy = w_done_pulse | w_abort_pulse;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_bd_rdy <= 1'b0;
        else if (r_rx_en && r_rx_en_q && r_bd_rd)
            r_bd_rdy <= i_db_rdata[BD_BIT_E];
        else if (w_rst_bd_rdy) r_bd_rdy <= 1'b0;

    // RX BD read
    reg                             r_bd_rd;
    reg                             r_blk_bd_rd;
    wire                            w_st_bd_rd;

    assign w_st_bd_rd = (w_retry_pkt | w_stt_wr) & ~r_blk_bd_rd & ~r_bd_rdy;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_bd_rd <= 1'b1;
        else if (w_st_bd_rd) r_bd_rd <= 1'b1;
        else if (r_bd_rdy) r_bd_rd <= 1'b0;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_blk_bd_rd <= 1'b0;
        else if (w_st_bd_rd) r_blk_bd_rd <= 1'b1;
        else if (~w_st_bd_rd && ~r_bd_rdy) r_blk_bd_rd <= 1'b0;

    // RX pointer read
    reg                             r_ptr_rd;
    wire                            w_st_ptr_rd;

    assign w_st_ptr_rd = r_bd_rd & r_bd_rdy;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_rd <= 1'b0;
        else if (w_st_ptr_rd) r_ptr_rd <= 1'b1;
        else if (r_rx_en && r_rx_en_q) r_ptr_rd <= 1'b0;

    // RX status from BD (control bits)
    reg [10:0]                      r_stt;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_stt <= 11'h0;
        else if (r_rx_en && r_rx_en_q && r_bd_rd)
            r_stt <= i_db_rdata[10:0];

    assign w_wrap = r_stt[BD_BIT_WR];
    wire                            w_irq_en = r_stt[BD_BIT_IRQ];

    // RX pointer
    reg [31:2]                      r_ptr_msb;
    reg [1:0]                       r_ptr_lsb;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_msb <= 30'h0;
        else if (r_rx_en && r_rx_en_q && r_ptr_rd) r_ptr_msb <= i_db_rdata[31:2];

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_lsb <= 2'b0;
        else if (r_rx_en && r_rx_en_q && r_ptr_rd) r_ptr_lsb <= i_db_rdata[1:0];

    // RX length counter (count received bytes)
    reg [15:0]                      r_rx_len;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_rx_len <= 16'h0;
        else if (r_rx_en && r_rx_en_q && r_bd_rd)
            r_rx_len <= 16'h0;
        else if (w_mac_rx_valid && w_mac_rx_start)
            r_rx_len <= 16'h0;
        else if (w_fifo_wr && ~i_fifo_full)
            r_rx_len <= r_rx_len + 16'd4;

    reg [15:0]                      r_rx_len_lat;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_rx_len_lat <= 16'h0;
        else if (r_rx_en && r_rx_en_q && r_bd_rd)
            r_rx_len_lat <= i_db_rdata[31:16];

    //===========================================================
    // MAC Interface Handler
    //===========================================================

    // Pulse detection
    wire                            w_done_pulse;
    wire                            w_abort_pulse;
    wire                            w_retry_pkt;

    assign w_done_pulse = w_mac_rx_end & ~r_mac_rx_end_d;
    assign w_abort_pulse = w_mac_rx_abort & ~r_mac_rx_abort_d;
    assign w_retry_pkt = 1'b0;  // RX doesn't have retry like TX

    // Packet flags
    reg                             r_done_pkt;
    reg                             r_abort_pkt;
    reg                             r_done_pkt_blocked;
    reg                             r_abort_pkt_blocked;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_done_pkt <= 1'b0;
        else if (w_done_pulse && !r_done_pkt_blocked)
            r_done_pkt <= 1'b1;
        else if (w_stt_wr)
            r_done_pkt <= 1'b0;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_abort_pkt <= 1'b0;
        else if (w_abort_pulse && !r_abort_pkt_blocked)
            r_abort_pkt <= 1'b1;
        else if (w_stt_wr)
            r_abort_pkt <= 1'b0;
    end

    // Blocked flags
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_done_pkt_blocked <= 1'b0;
        else if (~w_mac_rx_end && r_mac_rx_end_d)
            r_done_pkt_blocked <= 1'b0;
        else if (r_done_pkt)
            r_done_pkt_blocked <= 1'b1;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_abort_pkt_blocked <= 1'b0;
        else if (~w_mac_rx_abort && r_mac_rx_abort_d)
            r_abort_pkt_blocked <= 1'b0;
        else if (r_abort_pkt)
            r_abort_pkt_blocked <= 1'b1;
    end

    //===========================================================
    // RX Status Write
    //===========================================================
    reg                             r_stt_wr;
    reg                             r_blk_stt_wr;
    wire                            w_stt_wr;

    assign w_stt_wr = (r_done_pkt | r_abort_pkt) & r_rx_en & r_rx_en_q & ~r_blk_stt_wr;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_blk_stt_wr <= 1'b0;
        else if (~r_done_pkt && ~r_abort_pkt) r_blk_stt_wr <= 1'b0;
        else if (w_stt_wr) r_blk_stt_wr <= 1'b1;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_stt_wr <= 1'b0;
        else r_stt_wr <= w_stt_wr;

    // RX status bits to write to BD
    reg [8:0]                       r_rx_stt_in;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_rx_stt_in <= 9'h0;
        else if (r_rx_en && r_rx_en_q && r_bd_rd)
            r_rx_stt_in <= 9'h0;
        else if (w_stt_wr) begin
            r_rx_stt_in[0] <= 1'b1;  // E (Empty=0, has data=1)
            r_rx_stt_in[BD_BIT_LC] <= w_mac_rx_abort;
            r_rx_stt_in[BD_BIT_CRC] <= 1'b0;  // Would come from MAC CRC checker
            r_rx_stt_in[BD_BIT_SF] <= 1'b0;   // Would come from MAC
            r_rx_stt_in[BD_BIT_TL] <= 1'b0;   // Would come from MAC
            r_rx_stt_in[BD_BIT_IS] <= 1'b0;   // Would come from MAC
            r_rx_stt_in[BD_BIT_OR] <= 1'b0;   // Would come from MAC
        end

    wire [31:0]                      w_bd_din = {
        r_rx_len_lat,               // [31:16] LEN
        1'b1,                        // [15] E (Empty=0, has data)
        3'h0,                        // [14:12] Reserved
        r_rx_stt_in[8:0]            // [11:0] Status bits
    };

    // BD RAM control outputs
    always_comb begin
        o_db_rx_en = 1'b1;
        o_db_db_rd = r_bd_rd;
        o_db_ptr_rd = r_ptr_rd;
        o_db_stt_wr = r_stt_wr;
        o_db_wrap = w_wrap;
        o_db_wdata = w_bd_din;
    end

    wire [7:0]                       w_bd_addr = {1'b0, r_bd_addr};

    //===========================================================
    // FIFO Controller
    //===========================================================
    // RX: MAC writes to FIFO

    wire                             w_fifo_wr;
    assign w_fifo_wr = w_mac_rx_valid && r_rx_active && ~i_fifo_full;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_fifo_wr <= 1'b0;
            o_fifo_wdata <= 32'h0;
        end else begin
            o_fifo_wr <= w_fifo_wr;
            if (w_fifo_wr)
                o_fifo_wdata <= {24'h0, w_mac_rx_data};
        end
    end

    // FIFO clear on abort
    wire                             w_fifo_clear;
    assign w_fifo_clear = w_abort_pulse;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) o_fifo_clear <= 1'b0;
        else o_fifo_clear <= w_fifo_clear;

    //===========================================================
    // AHB Master Controller
    //===========================================================
    // RX: Write data from FIFO to memory

    reg                              r_ahb_tx;
    wire                             w_ahb_tx_req;

    assign w_ahb_tx_req = ~i_fifo_empty && r_rx_en && r_rx_en_q && r_rx_active;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ahb_tx <= 1'b0;
        else if (w_ahb_tx_req && ~r_ahb_tx) r_ahb_tx <= 1'b1;
        else if (i_ahb_err || (r_rx_len == 16'h0 && r_ptr_rd)) r_ahb_tx <= 1'b0;

    // AHB request
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) o_ahb_req <= 1'b0;
        else o_ahb_req <= r_ahb_tx;

    // Address generation
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_ahb_addr <= 30'h0;
            o_ahb_addr_lsb <= 2'h0;
        end else if (r_ahb_tx) begin
            o_ahb_addr <= r_ptr_msb;
            o_ahb_addr_lsb <= r_ptr_lsb;
        end
    end

    // Increment pointer after AHB ack
    reg                              r_incr_ptr;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_incr_ptr <= 1'b0;
        else if (i_ahb_ack && r_ahb_tx) r_incr_ptr <= 1'b1;
        else r_incr_ptr <= 1'b0;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) r_ptr_msb <= 30'h0;
        else if (r_incr_ptr) r_ptr_msb <= r_ptr_msb + 1'b1;

    // FIFO read
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) o_fifo_rd <= 1'b0;
        else o_fifo_rd <= i_ahb_ack && r_ahb_tx;

    // Length and burst
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_ahb_len <= 16'h0;
            o_ahb_burst_en <= 1'b0;
        end else begin
            o_ahb_len <= 16'd4;
            o_ahb_burst_en <= 1'b0;
        end
    end

    //===========================================================
    // Interrupt
    //===========================================================
    wire                             w_rx_error;
    assign w_rx_error = r_rx_stt_in[BD_BIT_CRC] |
                        r_rx_stt_in[BD_BIT_SF]  |
                        r_rx_stt_in[BD_BIT_TL]  |
                        r_rx_stt_in[BD_BIT_IS]  |
                        r_rx_stt_in[BD_BIT_OR];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_irq_done <= 1'b0;
        else if (r_done_pkt && w_irq_en)
            o_irq_done <= 1'b1;
        else
            o_irq_done <= 1'b0;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            o_irq_err <= 1'b0;
        else if (r_abort_pkt || w_rx_error)
            o_irq_err <= 1'b1;
        else
            o_irq_err <= 1'b0;
    end

endmodule
