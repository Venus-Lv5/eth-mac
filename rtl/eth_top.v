`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////
////  eth_top.v                                                   ////
////                                                              ////
////  Top-level Ethernet MAC with AHB-Lite Interface               ////
////                                                              ////
////  Based on ethmac eth_top.v, simplified per DESIGN_NOTES.md: ////
////    - AHB-Lite instead of WISHBONE                            ////
////    - 9 registers instead of 21                               ////
////    - PAD/CRC per-packet (in BD), not per-register           ////
////    - No MII Management (PHY pre-configured)                ////
////    - Fixed frame length: 64-1518 bytes                      ////
//////////////////////////////////////////////////////////////////////

module eth_top #(
    parameter TX_FIFO_DEPTH = 16,
    parameter RX_FIFO_DEPTH = 16,
    parameter TX_BD_NUM     = 64,
    parameter RX_BD_NUM     = 64,
    parameter BURST_LENGTH  = 4
)(
    //============================================================
    // AHB-Lite System Interface
    //============================================================
    input  wire                 i_hclk,
    input  wire                 i_hresetn,

    // Slave (from bus master/CPU)
    input  wire [9:0]           i_haddr,
    input  wire [2:0]           i_hburst,
    input  wire                 i_hmastlock,
    input  wire [3:0]           i_hprot,
    input  wire [2:0]           i_hsize,
    input  wire                 i_hsel,
    input  wire [1:0]           i_htrans,
    input  wire [31:0]          i_hwdata,
    input  wire                 i_hwrite,
    input  wire                 i_hready,

    output wire [31:0]          o_hrdata,
    output wire                 o_hreadyout,
    output wire                 o_hresp,

    // Master (to system RAM)
    input  wire                 i_hm_ready,
    input  wire [31:0]          i_hm_rdata,
    input  wire                 i_hm_resp,
    output wire [31:0]          o_hm_addr,
    output wire [2:0]           o_hm_burst,
    output wire                 o_hm_lock,
    output wire [3:0]           o_hm_prot,
    output wire [2:0]           o_hm_size,
    output wire [1:0]           o_hm_trans,
    output wire [31:0]          o_hm_wdata,
    output wire                 o_hm_write,
    output wire                 o_hm_sel,

    //============================================================
    // MII Interface (to PHY)
    //============================================================

    // TX Clock (from PHY)
    input  wire                 i_mtx_clk,

    // TX Outputs to PHY
    output wire [3:0]           o_mtxd,
    output wire                 o_mtxen,
    output wire                 o_mtxerr,

    // RX Clock (from PHY)
    input  wire                 i_mrx_clk,

    // RX Inputs from PHY
    input  wire [3:0]           i_mrxd,
    input  wire                 i_mrxdv,
    input  wire                 i_mrxerr,
    input  wire                 i_mcoll,
    input  wire                 i_mcrs,

    //============================================================
    // Interrupt Output
    //============================================================
    output wire                 o_irq
);

    //============================================================
    // Clock & Reset
    //============================================================
    wire                 w_clk;
    wire                 w_rst_n;

    assign w_clk   = i_hclk;
    assign w_rst_n = i_hresetn;

    //============================================================
    // Internal Wires
    //============================================================

    //-- AHB Slave Interface --
    wire                 w_reg_wr;
    wire                 w_reg_rd;
    wire [7:0]           w_reg_addr;
    wire [31:0]          w_reg_wdata;
    wire [31:0]          w_reg_rdata;

    wire                 w_bd_req;
    wire                 w_bd_wr;
    wire                 w_bd_rd;
    wire [9:0]           w_bd_addr;
    wire [31:0]          w_bd_wdata;
    wire [31:0]          w_bd_rdata;

    //-- Register Control Outputs --
    wire                 w_rx_en;
    wire                 w_tx_en;
    wire                 w_full_duplex;
    wire                 w_pro_en;
    wire                 w_bro_en;
    wire                 w_fil_en;
    wire [47:0]         w_mac_addr;
    wire [31:0]          w_hash_low;
    wire [31:0]          w_hash_high;
    wire                 w_tx_flow_en;
    wire                 w_rx_flow_en;
    wire                 w_pass_ctrl;

    //-- Interrupt Status/Enable --
    wire [6:0]           w_int_status;
    wire [6:0]          w_int_en;
    wire                 w_irq;

    //-- TX DMA Wires --
    wire                 w_txe_en;
    wire                 w_tx_db_rd;
    wire                 w_tx_ptr_rd;
    wire                 w_tx_stt_wr;
    wire                 w_tx_wrap;
    wire [31:0]          w_tx_bd_wdata;
    wire [31:0]          w_tx_bd_rdata;

    wire                 w_tx_fifo_wr;
    wire                 w_tx_fifo_rd;
    wire                 w_tx_fifo_full;
    wire                 w_tx_fifo_afull;
    wire                 w_tx_fifo_empty;
    wire                 w_tx_fifo_aempty;
    wire [$clog2(TX_FIFO_DEPTH):0] w_tx_fifo_cnt;
    wire [31:0]          w_tx_fifo_wdata;
    wire [31:0]          w_tx_fifo_rdata;

    wire                 w_tx_ahb_req;
    wire [31:2]          w_tx_ahb_addr;
    wire [1:0]           w_tx_ahb_addr_lsb;
    wire [15:0]           w_tx_ahb_len;
    wire                 w_tx_ahb_burst;
    wire                 w_tx_ahb_ack;
    wire                 w_tx_ahb_err;
    wire [31:0]          w_tx_ahb_rdata;

    wire                 w_tx_irq_done;
    wire                 w_tx_irq_err;

    //-- RX DMA Wires --
    wire                 w_rxe_en;
    wire                 w_rx_db_rd;
    wire                 w_rx_ptr_rd;
    wire                 w_rx_stt_wr;
    wire                 w_rx_wrap;
    wire [31:0]          w_rx_bd_wdata;
    wire [31:0]          w_rx_bd_rdata;

    wire                 w_rx_fifo_wr;
    wire                 w_rx_fifo_rd;
    wire                 w_rx_fifo_full;
    wire                 w_rx_fifo_afull;
    wire                 w_rx_fifo_empty;
    wire                 w_rx_fifo_aempty;
    wire [$clog2(RX_FIFO_DEPTH):0] w_rx_fifo_cnt;
    wire [31:0]          w_rx_fifo_wdata;
    wire [31:0]          w_rx_fifo_rdata;

    wire                 w_rx_ahb_req;
    wire [31:2]          w_rx_ahb_addr;
    wire [1:0]           w_rx_ahb_addr_lsb;
    wire [15:0]           w_rx_ahb_len;
    wire                 w_rx_ahb_burst;
    wire                 w_rx_ahb_ack;
    wire                 w_rx_ahb_err;

    wire                 w_rx_irq_done;
    wire                 w_rx_irq_err;
    wire                 w_rx_busy_irq;

    //-- TX MAC Interface --
    wire                 w_tx_start;
    wire                 w_tx_end;
    wire [7:0]           w_tx_data;
    wire                 w_tx_underrun;
    wire                 w_tx_crc;
    wire                 w_tx_pad;
    wire                 w_tx_used_data;
    wire                 w_tx_retry;
    wire                 w_tx_abort;
    wire                 w_tx_done;
    wire                 w_tx_defer;
    wire                 w_tx_retry_lmt;
    wire                 w_tx_late_coll;
    wire                 w_tx_carrier_lost;
    wire                 w_will_transmit;

    //-- RX MAC Interface --
    wire [7:0]           w_rx_data;
    wire                 w_rx_valid;
    wire                 w_rx_start;
    wire                 w_rx_end;
    wire                 w_rx_abort;
    wire [1:0]           w_rx_byte_cnt;
    wire                 w_rx_ready;

    //============================================================
    // MII SIGNAL SYNCHRONIZATION
    // Per ethmac eth_top.v lines 726-912
    //============================================================

    //-- TX Clock domain: Carrier Sense --
    // 2-FF synchronizer
    reg                  r_carrier_sync1;
    reg                  r_carrier_sync2;

    always @(posedge i_mtx_clk or negedge w_rst_n) begin
        if (!w_rst_n) begin
            r_carrier_sync1 <= 1'b0;
            r_carrier_sync2 <= 1'b0;
        end else begin
            r_carrier_sync1 <= i_mcrs;
            r_carrier_sync2 <= r_carrier_sync1;
        end
    end

    // Carrier sense only in half-duplex mode
    wire                 w_tx_carrier_sense;
    assign w_tx_carrier_sense = ~w_full_duplex & r_carrier_sync2;

    //-- TX Clock domain: Collision --
    // 2-FF synchronizer with ResetCollision control
    reg                  r_collision_sync1;
    reg                  r_collision_sync2;

    always @(posedge i_mtx_clk or negedge w_rst_n) begin
        if (!w_rst_n) begin
            r_collision_sync1 <= 1'b0;
            r_collision_sync2 <= 1'b0;
        end else begin
            r_collision_sync1 <= i_mcoll;
            // Reset collision when not transmitting
            if (w_will_transmit)
                r_collision_sync2 <= r_collision_sync1;
            else
                r_collision_sync2 <= 1'b0;
        end
    end

    // Collision only in half-duplex mode
    wire                 w_collision;
    assign w_collision = ~w_full_duplex & r_collision_sync2;

    //-- RX Clock domain: WillTransmit from TX MAC --
    // Used for collision detection in half-duplex mode
    reg                  r_will_tx_rx1;
    reg                  r_will_tx_rx2;

    always @(posedge i_mrx_clk) begin
        r_will_tx_rx1 <= w_will_transmit;
        r_will_tx_rx2 <= r_will_tx_rx1;
    end

    wire                 w_transmitting;
    assign w_transmitting = ~w_full_duplex & r_will_tx_rx2;

    //-- RX Clock domain: RxEn Sync --
    // Only update when MRxDV is low (per ethmac)
    reg                  r_rx_en_sync;

    always @(posedge i_mrx_clk or negedge w_rst_n) begin
        if (!w_rst_n)
            r_rx_en_sync <= 1'b0;
        else if (~i_mrxdv)
            r_rx_en_sync <= w_rx_en;
    end

    //-- MII RX Data/Valid (muxed for loopback - simplified, always use PHY input) --
    wire [3:0]          w_rx_mii_data;
    wire                 w_rx_mii_valid;
    wire                 w_rx_mii_err;

    assign w_rx_mii_data  = i_mrxd;
    assign w_rx_mii_valid = i_mrxdv & r_rx_en_sync;
    assign w_rx_mii_err   = i_mrxerr;

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
    // REGISTER FILE (9 registers per DESIGN_NOTES.md)
    //============================================================
    eth_register u_reg (
        .i_clk             (w_clk),
        .i_rst_n          (w_rst_n),

        .i_rd_en          (w_reg_rd),
        .i_wr_en          (w_reg_wr),
        .i_addr           (w_reg_addr),
        .i_wdata          (w_reg_wdata),
        .o_rdata          (w_reg_rdata),

        .o_rx_en          (w_rx_en),
        .o_tx_en          (w_tx_en),
        .o_bro_en         (w_bro_en),
        .o_fil_en         (w_fil_en),
        .o_pro_en         (w_pro_en),
        .o_full_en        (w_full_duplex),

        .o_mac_addr_low   (w_mac_addr[31:0]),
        .o_mac_addr_high  (w_mac_addr[47:32]),

        .o_hash_low       (w_hash_low),
        .o_hash_high      (w_hash_high),

        .o_tx_flow_en     (w_tx_flow_en),
        .o_rx_flow_en     (w_rx_flow_en),
        .o_pass_ctrl      (w_pass_ctrl),

        .o_send_pause     (),
        .o_pause_time    (),

        .o_tx_done        (w_int_status[0]),
        .o_tx_err         (w_int_status[1]),
        .o_rx_done        (w_int_status[2]),
        .o_rx_err         (w_int_status[3]),
        .o_rx_busy        (w_int_status[4]),
        .o_tx_ctrl_done   (w_int_status[5]),
        .o_rx_ctrl_done   (w_int_status[6]),

        .o_tx_done_en     (w_int_en[0]),
        .o_tx_err_en      (w_int_en[1]),
        .o_rx_done_en     (w_int_en[2]),
        .o_rx_err_en      (w_int_en[3]),
        .o_rx_busy_en     (w_int_en[4]),
        .o_tx_ctrl_en     (w_int_en[5]),
        .o_rx_ctrl_en     (w_int_en[6]),

        .i_tx_pause_done  (1'b0)
    );

    //============================================================
    // BD RAM (64 TX + 64 RX per DESIGN_NOTES.md)
    //============================================================
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
        .i_rst_n          (w_rst_n),

        .i_wr_en           (w_tx_fifo_wr),
        .i_rd_en           (w_tx_fifo_rd),
        .i_clear           (1'b0),

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
        .i_rst_n          (w_rst_n),

        .i_wr_en           (w_rx_fifo_wr),
        .i_rd_en           (w_rx_fifo_rd),
        .i_clear           (1'b0),

        .i_din             (w_rx_fifo_wdata),
        .o_dout            (w_rx_fifo_rdata),

        .o_full            (w_rx_fifo_full),
        .o_almost_full     (w_rx_fifo_afull),
        .o_empty           (w_rx_fifo_empty),
        .o_almost_empty    (w_rx_fifo_aempty),
        .o_count           (w_rx_fifo_cnt)
    );

    //============================================================
    // TX DMA ENGINE
    //============================================================
    eth_tx_dma #(
        .FifoDepth(TX_FIFO_DEPTH)
    ) u_tx_dma (
        .i_clk             (w_clk),
        .i_rst_n          (w_rst_n),

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
        .i_fifo_empty      (w_tx_fifo_empty),
        .i_fifo_almost_empty(w_tx_fifo_aempty),
        .i_fifo_count      (w_tx_fifo_cnt),
        .o_fifo_wr         (w_tx_fifo_wr),
        .o_fifo_rd         (w_tx_fifo_rd),
        .o_fifo_wdata      (w_tx_fifo_wdata),
        .o_fifo_clear      (),

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

        // MAC Interface
        .i_mac_clk          (i_mtx_clk),
        .i_mac_used_data    (w_tx_used_data),
        .i_mac_retry        (w_tx_retry),
        .i_mac_abort        (w_tx_abort),
        .i_mac_done         (w_tx_done),
        .i_mac_defer        (w_tx_defer),
        .i_mac_retry_lmt    (w_tx_retry_lmt),
        .i_mac_late_coll    (w_tx_late_coll),
        .i_mac_carry_lost   (w_tx_carrier_lost),
        .i_mac_retry_cnt    (4'h0),

        .o_mac_start        (w_tx_start),
        .o_mac_end         (w_tx_end),
        .o_mac_crc         (w_tx_crc),
        .o_mac_pad         (w_tx_pad),

        .o_irq_done         (w_tx_irq_done),
        .o_irq_err          (w_tx_irq_err),
        .o_mac_underrun    (w_tx_underrun)
    );

    //============================================================
    // RX DMA ENGINE
    //============================================================
    eth_rx_dma #(
        .FifoDepth(RX_FIFO_DEPTH),
        .BURST_LENGTH(BURST_LENGTH)
    ) u_rx_dma (
        .i_clk             (w_clk),
        .i_rst_n          (w_rst_n),

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
        .i_fifo_empty      (w_rx_fifo_empty),
        .i_fifo_almost_empty(w_rx_fifo_aempty),
        .i_fifo_count      (w_rx_fifo_cnt),
        .i_fifo_rdata       (w_rx_fifo_rdata),
        .o_fifo_wr         (w_rx_fifo_wr),
        .o_fifo_rd         (w_rx_fifo_rd),
        .o_fifo_wdata       (w_rx_fifo_wdata),
        .o_fifo_clear      (),

        // AHB Master
        .i_ahb_ack         (w_rx_ahb_ack),
        .i_ahb_err         (w_rx_ahb_err),
        .o_ahb_req         (w_rx_ahb_req),
        .o_ahb_addr        (w_rx_ahb_addr),
        .o_ahb_addr_lsb    (w_rx_ahb_addr_lsb),
        .o_ahb_len         (w_rx_ahb_len),
        .o_ahb_burst_en    (w_rx_ahb_burst),

        // Register
        .i_rx_en           (w_rx_en),

        // MAC Interface
        .i_mac_clk          (i_mrx_clk),
        .i_mac_rx_valid    (w_rx_valid),
        .i_mac_rx_start_frm (w_rx_start),
        .i_mac_rx_end_frm  (w_rx_end),
        .i_mac_rx_abort    (w_rx_abort),
        .i_mac_rx_data     (w_rx_data),
        .i_mac_rx_byte_cnt (w_rx_byte_cnt),

        .o_irq_done        (w_rx_irq_done),
        .o_irq_err         (w_rx_irq_err),
        .o_irq_busy        (w_rx_busy_irq)
    );

    //============================================================
    // AHB MASTER ARBITRATION (TX > RX priority)
    //============================================================
    eth_ahb_master #(
        .BURST_LENGTH(BURST_LENGTH),
        .BURST_CNT_WIDTH($clog2(BURST_LENGTH) + 1)
    ) u_master (
        .i_clk             (w_clk),
        .i_rst_n          (w_rst_n),

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

        // TX channel
        .i_tx_req          (w_tx_ahb_req),
        .i_tx_addr         (w_tx_ahb_addr),
        .i_tx_addr_lsb     (w_tx_ahb_addr_lsb),
        .i_tx_len          (w_tx_ahb_len),
        .i_tx_burst_en     (w_tx_ahb_burst),
        .o_tx_ack          (w_tx_ahb_ack),
        .o_tx_rdata        (w_tx_ahb_rdata),
        .o_tx_err          (w_tx_ahb_err),

        // RX channel
        .i_rx_req          (w_rx_ahb_req),
        .i_rx_addr         (w_rx_ahb_addr),
        .i_rx_addr_lsb     (w_rx_ahb_addr_lsb),
        .i_rx_len          (w_rx_ahb_len),
        .i_rx_wdata        (w_rx_fifo_rdata),
        .i_rx_burst_en     (w_rx_ahb_burst),
        .o_rx_ack          (w_rx_ahb_ack),
        .o_rx_err          (w_rx_ahb_err),

        .i_tx_en           (w_tx_en),
        .i_rx_en           (w_rx_en)
    );

    //============================================================
    // TX MAC MODULE
    //============================================================
    eth_tx_mac u_tx_mac (
        .i_clk            (i_mtx_clk),
        .i_rst_n          (w_rst_n),

        .i_tx_start        (w_tx_start),
        .i_tx_end          (w_tx_end),
        .i_tx_underrun    (w_tx_underrun),
        .i_tx_data        (w_tx_data),

        .i_pad_en          (w_tx_pad),
        .i_crc_en         (w_tx_crc),

        .i_full_duplex     (w_full_duplex),

        .i_carrier_sense  (w_tx_carrier_sense),
        .i_collision       (w_collision),

        .o_mtx_d           (o_mtxd),
        .o_mtx_en          (o_mtxen),
        .o_mtx_err         (o_mtxerr),

        .o_tx_done         (w_tx_done),
        .o_tx_retry        (w_tx_retry),
        .o_tx_abort        (w_tx_abort),
        .o_tx_used_data    (w_tx_used_data),

        .o_defer_ind       (w_tx_defer),
        .o_late_collision (w_tx_late_coll),
        .o_max_collision  (w_tx_retry_lmt),
        .o_will_transmit   (w_will_transmit)
    );

    // TX Data from FIFO (byte-wide to TX MAC)
    assign w_tx_data = w_tx_fifo_rdata[7:0];

    // TX Carrier Lost detection
    reg                  r_carrier_prev;

    always @(posedge i_mtx_clk or negedge w_rst_n) begin
        if (!w_rst_n)
            r_carrier_prev <= 1'b0;
        else
            r_carrier_prev <= r_carrier_sync2;
    end

    assign w_tx_carrier_lost = w_tx_start & r_carrier_prev & ~r_carrier_sync2;

    //============================================================
    // RX MAC MODULE
    //============================================================
    eth_rx_mac u_rx_mac (
        .i_clk            (i_mrx_clk),
        .i_rst_n          (w_rst_n),

        .i_rx_dv          (w_rx_mii_valid),
        .i_rx_data        (w_rx_mii_data),

        .i_rx_en          (w_rx_en),
        .i_transmitting    (w_transmitting),
        .i_pro            (w_pro_en),
        .i_bro            (w_bro_en),
        .i_pass_ctrl      (w_pass_ctrl),

        .i_mac_addr        (w_mac_addr),
        .i_hash0          (w_hash_low),
        .i_hash1          (w_hash_high),

        .i_ctrl_addr_ok    (1'b1),

        .o_rx_data        (w_rx_data),
        .o_rx_valid       (w_rx_valid),
        .o_rx_start       (w_rx_start),
        .o_rx_end         (w_rx_end),

        .o_rx_abort       (w_rx_abort),
        .o_rx_ready       (w_rx_ready)
    );

    // RX Byte Count - count valid bytes per cycle
    reg [1:0] r_rx_byte_cnt;

    always @(posedge i_mrx_clk or negedge w_rst_n) begin
        if (!w_rst_n)
            r_rx_byte_cnt <= 2'h0;
        else if (w_rx_start)
            r_rx_byte_cnt <= 2'h0;
        else if (w_rx_valid)
            r_rx_byte_cnt <= r_rx_byte_cnt + 2'h1;
        else if (w_rx_end)
            r_rx_byte_cnt <= 2'h0;
    end

    assign w_rx_byte_cnt = r_rx_byte_cnt;

    //============================================================
    // INTERRUPT OUTPUT
    // int_o = OR(irq_flag[i] & int_en[i])
    //============================================================
    assign w_irq = |(w_int_status & w_int_en);
    assign o_irq  = w_irq;

endmodule
