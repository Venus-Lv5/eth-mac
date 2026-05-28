`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////
////  eth_ahb_top.v                                                 ////
////                                                              ////
////  Top-level Ethernet MAC with AHB-Lite Interface              ////
////  - Integrates all submodules to mirror ETH_WISHBONE logic     ////
////  - AHB-Lite slave for register/BD access                     ////
////  - AHB-Lite master for DMA transfers                         ////
////  - MAC interface (byte-level, NOT MII)                      ////
//////////////////////////////////////////////////////////////////////

module eth_ahb_top #(
    parameter integer TX_FIFO_DEPTH = 16,
    parameter integer RX_FIFO_DEPTH = 16,
    parameter integer BURST_LENGTH  = 4
)(
    //============================================================
    // AHB-Lite System Interface
    //============================================================
    input  wire                 i_hclk,
    input  wire                 i_hresetn,

    // Slave (from bus master)
    input  wire [9:0]          i_haddr,
    input  wire [2:0]          i_hburst,
    input  wire                i_hmastlock,
    input  wire [3:0]          i_hprot,
    input  wire [2:0]          i_hsize,
    input  wire                i_hsel,
    input  wire [1:0]          i_htrans,
    input  wire [31:0]         i_hwdata,
    input  wire                i_hwrite,
    input  wire                i_hready,

    output wire [31:0]          o_hrdata,
    output wire                o_hreadyout,
    output wire                o_hresp,

    // Master (to system RAM)
    input  wire                i_hm_ready,
    input  wire [31:0]         i_hm_rdata,
    input  wire                i_hm_resp,
    output wire [31:0]          o_hm_addr,
    output wire [2:0]          o_hm_burst,
    output wire                o_hm_lock,
    output wire [3:0]          o_hm_prot,
    output wire [2:0]          o_hm_size,
    output wire [1:0]          o_hm_trans,
    output wire [31:0]          o_hm_wdata,
    output wire                o_hm_write,
    output wire                o_hm_sel,

    //============================================================
    // MAC Interface (byte-level, NOT MII)
    // Reference: eth_wishbone.v lines 273-401
    //============================================================

    //-- TX Clock (from PHY) --
    input  wire                i_mtx_clk,

    //-- TX Outputs to MAC --
    output wire                o_tx_start,      // Start frame
    output wire                o_tx_end,        // End frame
    output wire [7:0]         o_tx_data,       // Data byte (Big Endian)
    output wire                o_tx_underrun,    // Underrun flag
    output wire                o_tx_crc,        // Per-packet CRC enable
    output wire                o_tx_pad,        // Per-packet padding enable

    //-- TX Status Inputs from MAC --
    input  wire                i_tx_used_data,  // MAC consumed data
    input  wire                i_tx_retry,      // Retry (collision)
    input  wire                i_tx_abort,      // Abort request
    input  wire                i_tx_done,       // Transmission done
    input  wire [3:0]         i_tx_retry_cnt,  // Retry count
    input  wire                i_tx_retry_lmt,  // Retry limit reached
    input  wire                i_tx_late_coll,  // Late collision
    input  wire                i_tx_defer,      // Defer indication
    input  wire                i_tx_carrier_lost, // Carrier lost

    //-- RX Clock (from PHY) --
    input  wire                i_mrx_clk,

    //-- RX Data Inputs from MAC --
    input  wire [7:0]         i_rx_data,       // Received data byte
    input  wire                i_rx_valid,      // Data valid
    input  wire                i_rx_start,      // Start of frame
    input  wire                i_rx_end,        // End of frame
    input  wire                i_rx_abort,      // Abort (address mismatch)
    input  wire [1:0]         i_rx_byte_cnt,   // Valid byte count

    //============================================================
    // Interrupt Outputs
    //============================================================
    output wire                o_txb_irq,       // TX buffer complete
    output wire                o_txe_irq,       // TX error
    output wire                o_rxb_irq,       // RX buffer complete
    output wire                o_rxe_irq,       // RX error
    output wire                o_busy_irq       // Busy (no RX BD ready)
);

    //============================================================
    // Clock & Reset
    //============================================================
    wire                w_clk;
    wire                w_rst_n;

    assign w_clk   = i_hclk;
    assign w_rst_n = i_hresetn;

    //============================================================
    // Internal Wires
    //============================================================

    //-- Register --
    wire                 w_reg_wr;
    wire                 w_reg_rd;
    wire [7:0]          w_reg_addr;
    wire [31:0]         w_reg_wdata;
    wire [31:0]         w_reg_rdata;

    wire                 w_tx_en;
    wire                 w_rx_en;

    wire                 w_tx_pause_done;

    //-- BD RAM --
    wire                 w_bd_req;
    wire                 w_bd_wr;
    wire                 w_bd_rd;
    wire [9:0]          w_bd_addr;
    wire [31:0]         w_bd_wdata;
    wire [31:0]         w_bd_rdata;

    //-- TX DMA --
    wire                 w_txe_en;
    wire                 w_tx_db_rd;
    wire                 w_tx_ptr_rd;
    wire                 w_tx_stt_wr;
    wire                 w_tx_wrap;
    wire [31:0]         w_tx_bd_wdata;
    wire [31:0]         w_tx_bd_rdata;

    wire                 w_tx_ahb_req;
    wire [31:2]         w_tx_ahb_addr;
    wire [1:0]          w_tx_ahb_addr_lsb;
    wire [15:0]         w_tx_ahb_len;
    wire                 w_tx_ahb_burst;
    wire                 w_tx_ahb_ack;
    wire                 w_tx_ahb_err;
    wire [31:0]         w_tx_ahb_rdata;

    wire                 w_tx_irq_done;
    wire                 w_tx_irq_err;
    wire                 w_tx_underrun;

    //-- RX DMA --
    wire                 w_rxe_en;
    wire                 w_rx_db_rd;
    wire                 w_rx_ptr_rd;
    wire                 w_rx_stt_wr;
    wire                 w_rx_wrap;
    wire [31:0]         w_rx_bd_wdata;
    wire [31:0]         w_rx_bd_rdata;

    wire                 w_rx_ahb_req;
    wire [31:2]         w_rx_ahb_addr;
    wire [1:0]          w_rx_ahb_addr_lsb;
    wire [15:0]         w_rx_ahb_len;
    wire [31:0]         w_rx_ahb_wdata;
    wire                 w_rx_ahb_burst;
    wire                 w_rx_ahb_ack;
    wire                 w_rx_ahb_err;

    wire                 w_rx_irq_done;
    wire                 w_rx_irq_err;
    wire                 w_rx_busy_irq;

    //-- FIFO --
    wire [31:0]         w_tx_fifo_wdata;
    wire [31:0]         w_tx_fifo_rdata;
    wire                 w_tx_fifo_wr;
    wire                 w_tx_fifo_rd;
    wire                 w_tx_fifo_clr;
    wire                 w_tx_fifo_full;
    wire                 w_tx_fifo_afull;
    wire                 w_tx_fifo_empty;
    wire                 w_tx_fifo_aempty;
    wire [$clog2(TX_FIFO_DEPTH):0] w_tx_fifo_cnt;

    wire [31:0]         w_rx_fifo_wdata;
    wire [31:0]         w_rx_fifo_rdata;
    wire                 w_rx_fifo_wr;
    wire                 w_rx_fifo_rd;
    wire                 w_rx_fifo_clr;
    wire                 w_rx_fifo_full;
    wire                 w_rx_fifo_afull;
    wire                 w_rx_fifo_empty;
    wire                 w_rx_fifo_aempty;
    wire [$clog2(RX_FIFO_DEPTH):0] w_rx_fifo_cnt;

    //-- RX byte assembly registers (internal) --
    reg [31:0]         r_rx_fifo_wdata_byte;
    reg                 r_rx_fifo_wr_byte;

    //-- RX DMA FIFO outputs (intermediate) --
    wire                 w_rx_dma_fifo_wr;
    wire [31:0]         w_rx_dma_fifo_wdata;

    //-- Interrupt --
    wire [6:0]           w_int_en;
    wire [6:0]          w_irq_flags;

    //============================================================
    // AHB SLAVE - Register & BD Access
    //============================================================
    eth_ahb_slave #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(32)
    ) u_slave (
        .i_HCLK        (w_clk),
        .i_HRESET_n    (w_rst_n),
        .i_HADDR       (i_haddr),
        .i_HTRANS      (i_htrans),
        .i_HWRITE      (i_hwrite),
        .i_HSIZE       (i_hsize),
        .i_HBURST      (i_hburst),
        .i_HWDATA      (i_hwdata),
        .i_HSEL        (i_hsel),
        .i_HREADY      (i_hready),
        .o_HRDATA      (o_hrdata),
        .o_HREADYOUT   (o_hreadyout),
        .o_HRESP       (o_hresp),

        // Register
        .o_reg_wr_en   (w_reg_wr),
        .o_reg_rd_en   (w_reg_rd),
        .o_reg_addr    (w_reg_addr),
        .o_reg_wdata   (w_reg_wdata),
        .i_reg_rdata   (w_reg_rdata),

        // BD
        .o_bd_wr_en    (w_bd_wr),
        .o_bd_rd_en    (w_bd_rd),
        .o_bd_addr     (w_bd_addr),
        .o_bd_wdata    (w_bd_wdata),
        .i_bd_rdata    (w_bd_rdata)
    );

    assign w_bd_req = w_bd_wr | w_bd_rd;

    //============================================================
    // REGISTER FILE
    //============================================================
    eth_register u_reg (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        .i_rd_en           (w_reg_rd),
        .i_wr_en           (w_reg_wr),
        .i_addr            (w_reg_addr),
        .i_wdata           (w_reg_wdata),
        .o_rdata           (w_reg_rdata),

        .o_rx_en           (w_rx_en),
        .o_tx_en           (w_tx_en),

        .i_tx_pause_done   (w_tx_pause_done)
    );

    //============================================================
    // BD RAM
    // TX_BD_NUM = 64 fixed, RX_BD_NUM = 64 fixed
    //============================================================
    localparam integer TX_BD_NUM = 64;
    localparam integer RX_BD_NUM = 64;

    eth_bd_ram #(
        .TX_BD_NUM(TX_BD_NUM),
        .RX_BD_NUM(RX_BD_NUM)
    ) u_bd_ram (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        // AHB slave access
        .i_ahb_req         (w_bd_req),
        .i_ahb_wr          (w_bd_wr),
        .i_ahb_be          (4'hF),
        .i_ahb_addr        (w_bd_addr),
        .i_ahb_wdata       (w_bd_wdata),
        .o_ahb_rdata       (w_bd_rdata),

        // TX DMA
        .i_txe_en          (w_txe_en),
        .i_tx_db_rd        (w_tx_db_rd),
        .i_tx_ptr_rd       (w_tx_ptr_rd),
        .i_tx_stt_wr       (w_tx_stt_wr),
        .i_tx_wrap         (w_tx_wrap),
        .i_tx_wdata        (w_tx_bd_wdata),
        .o_tx_rdata        (w_tx_bd_rdata),

        // RX DMA
        .i_rxe_en          (w_rxe_en),
        .i_rx_db_rd        (w_rx_db_rd),
        .i_rx_ptr_rd       (w_rx_ptr_rd),
        .i_rx_stt_wr       (w_rx_stt_wr),
        .i_rx_wrap         (w_rx_wrap),
        .i_rx_wdata        (w_rx_bd_wdata),
        .o_rx_rdata        (w_rx_bd_rdata)
    );

    //============================================================
    // TX FIFO
    //============================================================
    eth_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        .i_wr_en           (w_tx_fifo_wr),
        .i_rd_en           (w_tx_fifo_rd),
        .i_clear           (w_tx_fifo_clr),

        .i_din             (w_tx_fifo_wdata),
        .o_dout            (w_tx_fifo_rdata),

        .o_full            (w_tx_fifo_full),
        .o_almost_full     (w_tx_fifo_afull),
        .o_empty           (w_tx_fifo_empty),
        .o_almost_empty    (w_tx_fifo_aempty),
        .o_count           (w_tx_fifo_cnt)
    );

    //============================================================
    // RX FIFO
    //============================================================
    eth_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        .i_wr_en           (r_rx_fifo_wr_byte),
        .i_rd_en           (w_rx_fifo_rd),
        .i_clear           (w_rx_fifo_clr),

        .i_din             (r_rx_fifo_wdata_byte),
        .o_dout            (w_rx_fifo_rdata),

        .o_full            (w_rx_fifo_full),
        .o_almost_full     (w_rx_fifo_afull),
        .o_empty           (w_rx_fifo_empty),
        .o_almost_empty    (w_rx_fifo_aempty),
        .o_count           (w_rx_fifo_cnt)
    );

    //============================================================
    // TX DMA ENGINE
    // CDC handled INSIDE this module (see eth_tx_dma.v)
    //============================================================
    eth_tx_dma #(
        .FifoDepth(TX_FIFO_DEPTH)
    ) u_tx_dma (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        // BD RAM
        .i_db_rdata        (w_tx_bd_rdata),
        .o_db_tx_en        (w_txe_en),
        .o_db_db_rd        (w_tx_db_rd),
        .o_db_ptr_rd       (w_tx_ptr_rd),
        .o_db_stt_wr       (w_tx_stt_wr),
        .o_db_wrap         (w_tx_wrap),
        .o_db_wdata        (w_tx_bd_wdata),

        // FIFO
        .i_fifo_full       (w_tx_fifo_full),
        .i_fifo_almost_full (w_tx_fifo_afull),
        .i_fifo_empty       (w_tx_fifo_empty),
        .i_fifo_almost_empty(w_tx_fifo_aempty),
        .i_fifo_count       (w_tx_fifo_cnt),
        .o_fifo_wr         (w_tx_fifo_wr),
        .o_fifo_rd         (w_tx_fifo_rd),
        .o_fifo_wdata      (w_tx_fifo_wdata),
        .o_fifo_clear      (w_tx_fifo_clr),

        // AHB Master
        .i_ahb_ack         (w_tx_ahb_ack),
        .i_ahb_err         (w_tx_ahb_err),
        .i_ahb_rdata       (w_tx_ahb_rdata),
        .o_ahb_req         (w_tx_ahb_req),
        .o_ahb_addr        (w_tx_ahb_addr),
        .o_ahb_addr_lsb    (w_tx_ahb_addr_lsb),
        .o_ahb_len         (w_tx_ahb_len),
        .o_ahb_burst_en    (w_tx_ahb_burst),

        // Register
        .i_tx_en           (w_tx_en),

        // MAC Interface (with CDC inside)
        .i_mac_clk         (i_mtx_clk),
        .i_mac_used_data  (i_tx_used_data),
        .i_mac_retry       (i_tx_retry),
        .i_mac_abort       (i_tx_abort),
        .i_mac_done        (i_tx_done),
        .i_mac_defer       (i_tx_defer),
        .i_mac_retry_lmt   (i_tx_retry_lmt),
        .i_mac_late_coll   (i_tx_late_coll),
        .i_mac_carry_lost  (i_tx_carrier_lost),
        .i_mac_retry_cnt   (i_tx_retry_cnt),

        .o_mac_start       (o_tx_start),
        .o_mac_end         (o_tx_end),
        .o_mac_crc         (o_tx_crc),
        .o_mac_pad         (o_tx_pad),

        .o_irq_done        (w_tx_irq_done),
        .o_irq_err         (w_tx_irq_err),
        .o_mac_underrun    (w_tx_underrun)
    );

    //============================================================
    // TX BYTE SELECTION
    // Converts 32-bit FIFO data (on i_clk) to 8-bit MAC data (on MTxClk)
    // CDC: FIFO data (i_clk) -> MTxClk domain -> byte selection
    //============================================================

    //-- CDC: TX FIFO read data to MTxClk domain (2-FF synchronizer) --
    reg [31:0] r_tx_fifo_sync1;
    reg [31:0] r_tx_fifo_sync2;

    always @(posedge i_mtx_clk or negedge i_hresetn) begin
        if (!i_hresetn) begin
            r_tx_fifo_sync1 <= 32'h0;
            r_tx_fifo_sync2 <= 32'h0;
        end else begin
            r_tx_fifo_sync1 <= w_tx_fifo_rdata;
            r_tx_fifo_sync2 <= r_tx_fifo_sync1;
        end
    end

    //-- CDC: TX control signals to MTxClk domain --
    reg r_tx_start_sync1;
    reg r_tx_start_sync2;
    reg r_tx_start_d;

    always @(posedge i_mtx_clk or negedge i_hresetn) begin
        if (!i_hresetn) begin
            r_tx_start_sync1 <= 1'b0;
            r_tx_start_sync2 <= 1'b0;
            r_tx_start_d <= 1'b0;
        end else begin
            r_tx_start_sync1 <= o_tx_start;
            r_tx_start_sync2 <= r_tx_start_sync1;
            r_tx_start_d <= r_tx_start_sync2;
        end
    end

    wire w_tx_start_pulse;
    assign w_tx_start_pulse = r_tx_start_sync2 & ~r_tx_start_d;

    //-- TX Byte Counter (on MTxClk domain) --
    // Counts 0->1->2->3 within each 32-bit word
    reg [1:0] r_tx_byte_cnt;

    always @(posedge i_mtx_clk or negedge i_hresetn) begin
        if (!i_hresetn)
            r_tx_byte_cnt <= 2'h0;
        else if (w_tx_start_pulse)
            // Reset on start frame
            r_tx_byte_cnt <= 2'h0;
        else if (i_tx_used_data)
            // Increment when MAC consumes a byte
            r_tx_byte_cnt <= r_tx_byte_cnt + 1'b1;
    end

    //-- TX Data Latch (latch new word when counter wraps) --
    reg [31:0] r_tx_data_latched;

    always @(posedge i_mtx_clk or negedge i_hresetn) begin
        if (!i_hresetn)
            r_tx_data_latched <= 32'h0;
        else if (w_tx_start_pulse)
            // Latch on start frame
            r_tx_data_latched <= r_tx_fifo_sync2;
        else if (i_tx_used_data && (r_tx_byte_cnt == 2'h3))
            // Latch new word when current word is exhausted
            r_tx_data_latched <= r_tx_fifo_sync2;
    end

    //-- TX Data Output: select byte based on counter (Big Endian) --
    // Reference: eth_wishbone.v lines 1729-1734
    reg [7:0] r_tx_data_out;

    always @(posedge i_mtx_clk or negedge i_hresetn) begin
        if (!i_hresetn)
            r_tx_data_out <= 8'h0;
        else if (i_tx_used_data) begin
            case (r_tx_byte_cnt)
                2'h0: r_tx_data_out <= r_tx_data_latched[31:24];  // Byte 0 (MSB)
                2'h1: r_tx_data_out <= r_tx_data_latched[23:16];  // Byte 1
                2'h2: r_tx_data_out <= r_tx_data_latched[15:08];  // Byte 2
                2'h3: r_tx_data_out <= r_tx_data_latched[07:00];  // Byte 3 (LSB)
            endcase
        end
    end

    assign o_tx_data = r_tx_data_out;
    assign o_tx_underrun = w_tx_underrun;

    //============================================================
    // RX BYTE ASSEMBLY
    // CDC: MAC data (MRxClk) -> i_clk domain -> 32-bit word -> FIFO (i_clk)
    // Note: Since FIFO runs on i_clk, assembly is done on i_clk after CDC
    //============================================================

    //-- CDC: RX data from MRxClk to i_clk domain (2-FF synchronizer) --
    reg [7:0]  r_rx_data_sync1;
    reg [7:0]  r_rx_data_sync2;
    reg        r_rx_valid_sync1;
    reg        r_rx_valid_sync2;
    reg        r_rx_start_sync1;
    reg        r_rx_start_sync2;
    reg        r_rx_end_sync1;
    reg        r_rx_end_sync2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_data_sync1  <= 8'h0;
            r_rx_data_sync2  <= 8'h0;
            r_rx_valid_sync1 <= 1'b0;
            r_rx_valid_sync2 <= 1'b0;
            r_rx_start_sync1 <= 1'b0;
            r_rx_start_sync2 <= 1'b0;
            r_rx_end_sync1   <= 1'b0;
            r_rx_end_sync2   <= 1'b0;
        end else begin
            r_rx_data_sync1  <= i_rx_data;
            r_rx_data_sync2  <= r_rx_data_sync1;
            r_rx_valid_sync1 <= i_rx_valid;
            r_rx_valid_sync2 <= r_rx_valid_sync1;
            r_rx_start_sync1 <= i_rx_start;
            r_rx_start_sync2 <= r_rx_start_sync1;
            r_rx_end_sync1   <= i_rx_end;
            r_rx_end_sync2   <= r_rx_end_sync1;
        end
    end

    wire w_rx_valid;
    wire w_rx_start;
    wire w_rx_end;
    assign w_rx_valid = r_rx_valid_sync2;
    assign w_rx_start = r_rx_start_sync2;
    assign w_rx_end   = r_rx_end_sync2;

    //-- RX Byte Counter (on i_clk domain) --
    reg [1:0] r_rx_byte_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_byte_cnt <= 2'h0;
        else if (w_rx_start)
            // Reset on start frame
            r_rx_byte_cnt <= 2'h0;
        else if (w_rx_valid && ~w_rx_fifo_full)
            // Increment when valid byte received and FIFO not full
            r_rx_byte_cnt <= r_rx_byte_cnt + 1'b1;
    end

    //-- RX Word Assembly (Big Endian, on i_clk domain) --
    // Reference: eth_wishbone.v lines 2159-2167
    reg [31:0] r_rx_word;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_word <= 32'h0;
        else if (w_rx_start)
            // Initialize with first byte on start frame
            r_rx_word <= {24'h0, r_rx_data_sync2};
        else if (w_rx_valid && ~w_rx_fifo_full) begin
            case (r_rx_byte_cnt)
                2'h0: r_rx_word[31:24] <= r_rx_data_sync2;
                2'h1: r_rx_word[23:16] <= r_rx_data_sync2;
                2'h2: r_rx_word[15:8]  <= r_rx_data_sync2;
                2'h3: r_rx_word[7:0]   <= r_rx_data_sync2;  // Full word assembled
            endcase
        end
    end

    //============================================================
    // RX DMA ENGINE
    // CDC handled INSIDE this module (see eth_rx_dma.v)
    //============================================================
    eth_rx_dma #(
        .FifoDepth(RX_FIFO_DEPTH)
    ) u_rx_dma (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        // BD RAM
        .i_db_rdata        (w_rx_bd_rdata),
        .o_db_rx_en        (w_rxe_en),
        .o_db_db_rd        (w_rx_db_rd),
        .o_db_ptr_rd       (w_rx_ptr_rd),
        .o_db_stt_wr       (w_rx_stt_wr),
        .o_db_wrap         (w_rx_wrap),
        .o_db_wdata        (w_rx_bd_wdata),

        // FIFO
        .i_fifo_full       (w_rx_fifo_full),
        .i_fifo_almost_full (w_rx_fifo_afull),
        .i_fifo_empty       (w_rx_fifo_empty),
        .i_fifo_almost_empty(w_rx_fifo_aempty),
        .i_fifo_count       (w_rx_fifo_cnt),
        .i_fifo_rdata       (w_rx_fifo_rdata),
        .o_fifo_wr         (w_rx_dma_fifo_wr),
        .o_fifo_rd         (w_rx_fifo_rd),
        .o_fifo_wdata      (w_rx_dma_fifo_wdata),
        .o_fifo_clear      (w_rx_fifo_clr),

        // AHB Master
        .i_ahb_ack         (w_rx_ahb_ack),
        .i_ahb_err         (w_rx_ahb_err),
        .i_ahb_rdata       (32'h0),
        .o_ahb_req         (w_rx_ahb_req),
        .o_ahb_addr        (w_rx_ahb_addr),
        .o_ahb_addr_lsb    (w_rx_ahb_addr_lsb),
        .o_ahb_len         (w_rx_ahb_len),
        .o_ahb_burst_en    (w_rx_ahb_burst),

        // Register
        .i_rx_en           (w_rx_en),

        // MAC Interface (with CDC inside)
        .i_mac_clk         (i_mrx_clk),
        .i_mac_rx_valid   (i_rx_valid),
        .i_mac_rx_start_frm (i_rx_start),
        .i_mac_rx_end_frm (i_rx_end),
        .i_mac_rx_abort   (i_rx_abort),
        .i_mac_rx_data    (i_rx_data),
        .i_mac_rx_byte_cnt (i_rx_byte_cnt),

        .o_irq_done        (w_rx_irq_done),
        .o_irq_err         (w_rx_irq_err),
        .o_irq_busy        (w_rx_busy_irq)
    );

    //============================================================
    // RX BYTE ASSEMBLY -> FIFO WRITE
    // Byte assembly on i_clk domain (after CDC from MRxClk)
    // Write to FIFO when word assembly is complete (byte_cnt wraps)
    //============================================================

    //-- Generate FIFO write when word is complete --
    // Priority: byte assembly > RX DMA (if both have data)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_fifo_wr_byte <= 1'b0;
            r_rx_fifo_wdata_byte <= 32'h0;
        end else begin
            // Default: pass through RX DMA data if no byte assembly write
            r_rx_fifo_wr_byte <= w_rx_dma_fifo_wr;
            r_rx_fifo_wdata_byte <= w_rx_dma_fifo_wdata;

            // Override with byte assembly data when word is complete
            if ((r_rx_byte_cnt == 2'h3) && w_rx_valid && ~w_rx_fifo_full) begin
                r_rx_fifo_wr_byte <= 1'b1;
                r_rx_fifo_wdata_byte <= r_rx_word;
            end
        end
    end

    //============================================================
    // AHB MASTER ARBITRATION
    //============================================================
    eth_ahb_master #(
        .BURST_LENGTH(BURST_LENGTH),
        .BURST_CNT_WIDTH($clog2(BURST_LENGTH) + 1)
    ) u_master (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),

        // AHB outputs
        .o_haddr           (o_hm_addr),
        .o_hburst          (o_hm_burst),
        .o_hmastlock       (o_hm_lock),
        .o_hprot           (o_hm_prot),
        .o_hsize           (o_hm_size),
        .o_htrans          (o_hm_trans),
        .o_hwdata          (o_hm_wdata),
        .o_hwrite          (o_hm_write),
        .o_hsel            (o_hm_sel),
        .i_hrdata          (i_hm_rdata),
        .i_hready          (i_hm_ready),
        .i_hresp           (i_hm_resp),

        // TX channel (read from memory)
        .i_tx_req          (w_tx_ahb_req),
        .i_tx_addr         (w_tx_ahb_addr),
        .i_tx_addr_lsb     (w_tx_ahb_addr_lsb),
        .i_tx_len          (w_tx_ahb_len),
        .i_tx_burst_en     (w_tx_ahb_burst),
        .o_tx_ack          (w_tx_ahb_ack),
        .o_tx_rdata        (w_tx_ahb_rdata),
        .o_tx_err          (w_tx_ahb_err),

        // RX channel (write to memory)
        .i_rx_req          (w_rx_ahb_req),
        .i_rx_addr         (w_rx_ahb_addr),
        .i_rx_addr_lsb     (w_rx_ahb_addr_lsb),
        .i_rx_len          (w_rx_ahb_len),
        .i_rx_wdata        (w_rx_fifo_rdata),
        .i_rx_burst_en     (w_rx_ahb_burst),
        .o_rx_ack          (w_rx_ahb_ack),
        .o_rx_err          (w_rx_ahb_err),
        .o_rx_ptr_inc      (),

        .i_tx_en           (w_tx_en),
        .i_rx_en           (w_rx_en)
    );

    //============================================================
    // INTERRUPT CONTROLLER
    //============================================================
    eth_interrupt u_int (
        .i_clk             (w_clk),
        .i_rst_n           (w_rst_n),
        .i_mac_clk         (i_mrx_clk),

        .i_tx_done         (w_tx_irq_done),
        .i_tx_err          (w_tx_irq_err),
        .i_rx_done         (w_rx_irq_done),
        .i_rx_err          (w_rx_irq_err),
        .i_rx_busy         (w_rx_busy_irq),
        .i_tx_ctrl_done    (1'b0),
        .i_rx_ctrl_done    (1'b0),

        .i_int_en          (7'h0),  // Default: all disabled

        .i_status_wr       (w_reg_wr & (w_reg_addr == 8'h01)),
        .i_status_wr_data   (w_reg_wdata[6:0]),

        .o_irq_flags       (w_irq_flags)
    );

    assign o_txb_irq = w_irq_flags[0];
    assign o_txe_irq = w_irq_flags[1];
    assign o_rxb_irq = w_irq_flags[2];
    assign o_rxe_irq = w_irq_flags[3];
    assign o_busy_irq = w_irq_flags[4];

endmodule
