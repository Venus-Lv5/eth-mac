`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Ethernet MAC top-level buffer-based
//
// Chuc nang:
// - Giu interface ngoai giong eth_top.v cu de de thay the.
// - Bo datapath DMA/BD/AHB master, chi dung AHB slave register.
// - Noi TX/RX ping-pong frame buffer voi MAC TX/RX.
// - Uu tien gui PAUSE frame tu dong khi RX buffer day.
//
// Ghi chu:
// - AHB master legacy duoc tie-off idle vi DMA da bi bo.
// - Top khong chua FSM datapath lon; FSM nam trong cac module con.
// - Config tu AHB sang MII clock duoc sync bang 2 FF. Firmware nen doi
//   cau hinh khi TX/RX dang disable hoac idle.
//------------------------------------------------------------------------------
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

    //============================================================
    // MII Interface (to PHY)
    //============================================================
    input  wire                 i_mtx_clk,
    output wire [3:0]           o_mtxd,
    output wire                 o_mtxen,
    output wire                 o_mtxerr,

    input  wire                 i_mrx_clk,
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


    //--------------------------------------------------------------------------
    // AHB slave -> register
    //--------------------------------------------------------------------------
    wire        w_reg_wr_en;
    wire        w_reg_rd_en;
    wire [7:0]  w_reg_addr;
    wire [31:0] w_reg_wdata;
    wire [31:0] w_reg_rdata;
    wire        w_reg_error;

    eth_ahb_slave #(
        .DATA_WIDTH (32)
    ) u_ahb_slave (
        .i_HCLK       (i_hclk),
        .i_HRESET_n   (i_hresetn),
        .i_HADDR      (i_haddr),
        .i_HTRANS     (i_htrans),
        .i_HWRITE     (i_hwrite),
        .i_HSIZE      (i_hsize),
        .i_HBURST     (i_hburst),
        .i_HWDATA     (i_hwdata),
        .i_HSEL       (i_hsel),
        .i_HREADY     (i_hready),
        .o_HRDATA     (o_hrdata),
        .o_HREADYOUT  (o_hreadyout),
        .o_HRESP      (o_hresp),
        .o_reg_wr_en  (w_reg_wr_en),
        .o_reg_rd_en  (w_reg_rd_en),
        .o_reg_addr   (w_reg_addr),
        .o_reg_wdata  (w_reg_wdata),
        .i_reg_rdata  (w_reg_rdata),
        .i_reg_error  (w_reg_error)
    );

    //--------------------------------------------------------------------------
    // Register file
    //--------------------------------------------------------------------------
    wire        w_rx_en_ahb;
    wire        w_tx_en_ahb;
    wire        w_bro_en_ahb;
    wire        w_fil_en_ahb;
    wire        w_pro_en_ahb;
    wire        w_full_duplex_ahb;
    wire [47:0] w_tx_da_ahb;
    wire [47:0] w_mac_sa_ahb;
    wire [31:0] w_hash_low_ahb;
    wire [31:0] w_hash_high_ahb;

    wire        w_tx_len_wr_en;
    wire [15:0] w_tx_len;
    wire        w_tx_payload_wr_en;
    wire [31:0] w_tx_payload_wdata;
    wire        w_tx_start_pulse;
    wire        w_tx_ready_ahb;
    wire        w_tx_busy_ahb;
    wire        w_tx_sw_err_pulse_ahb;
    wire        w_tx_done_pulse_ahb;
    wire        w_tx_err_pulse_ahb;

    wire        w_rx_payload_rd_en;
    wire [31:0] w_rx_payload_rdata;
    wire        w_rx_avail_ahb;
    wire [15:0] w_rx_len_ahb;
    wire        w_rx_release_pulse;
    wire        w_rx_sw_err_pulse_ahb;
    wire        w_rx_busy_pulse_ahb;
    wire        w_rx_err_pulse_ahb;

    wire        w_tx_pause_req_ahb;
    wire        w_rx_pause_active_ahb;
    wire        w_rx_pause_seen_pulse_ahb;
    wire        w_tx_pause_en_ahb;
    wire        w_rx_pause_en_ahb;

    eth_register u_register (
        .i_clk                  (i_hclk),
        .i_rst_n                (i_hresetn),
        .i_rd_en                (w_reg_rd_en),
        .i_wr_en                (w_reg_wr_en),
        .i_addr                 (w_reg_addr),
        .i_wdata                (w_reg_wdata),
        .o_rdata                (w_reg_rdata),
        .o_reg_error            (w_reg_error),
        .o_rx_en                (w_rx_en_ahb),
        .o_tx_en                (w_tx_en_ahb),
        .o_bro_en               (w_bro_en_ahb),
        .o_fil_en               (w_fil_en_ahb),
        .o_pro_en               (w_pro_en_ahb),
        .o_full_duplex          (w_full_duplex_ahb),
        .o_tx_da                (w_tx_da_ahb),
        .o_mac_sa               (w_mac_sa_ahb),
        .o_hash_low             (w_hash_low_ahb),
        .o_hash_high            (w_hash_high_ahb),
        .o_tx_len_wr_en         (w_tx_len_wr_en),
        .o_tx_len               (w_tx_len),
        .o_tx_payload_wr_en     (w_tx_payload_wr_en),
        .o_tx_payload_wdata     (w_tx_payload_wdata),
        .o_tx_start_pulse       (w_tx_start_pulse),
        .i_tx_ready             (w_tx_ready_ahb),
        .i_tx_busy              (w_tx_busy_ahb),
        .i_tx_sw_err_pulse      (w_tx_sw_err_pulse_ahb),
        .o_rx_payload_rd_en     (w_rx_payload_rd_en),
        .i_rx_payload_rdata     (w_rx_payload_rdata),
        .i_rx_avail             (w_rx_avail_ahb),
        .i_rx_len               (w_rx_len_ahb),
        .o_rx_release_pulse     (w_rx_release_pulse),
        .i_rx_sw_err_pulse      (w_rx_sw_err_pulse_ahb),
        .i_tx_done_pulse        (w_tx_done_pulse_ahb),
        .i_tx_err_pulse         (w_tx_err_pulse_ahb),
        .i_rx_busy_pulse        (w_rx_busy_pulse_ahb),
        .i_rx_err_pulse         (w_rx_err_pulse_ahb),
        .i_tx_pause_req         (w_tx_pause_req_ahb),
        .i_rx_pause_active      (w_rx_pause_active_ahb),
        .i_rx_pause_seen_pulse  (w_rx_pause_seen_pulse_ahb),
        .o_tx_pause_en          (w_tx_pause_en_ahb),
        .o_rx_pause_en          (w_rx_pause_en_ahb),
        .o_int_en               (),
        .o_irq                  (o_irq)
    );

    //--------------------------------------------------------------------------
    // Config sync
    //--------------------------------------------------------------------------
    wire [50:0] w_tx_cfg_tx;
    wire [116:0] w_rx_cfg_rx;
    wire        w_rx_en_sync;
    wire        w_tx_en_tx;
    wire        w_full_duplex_tx;
    wire        w_tx_pause_en_tx;
    wire [47:0] w_mac_sa_tx;
    wire        w_full_duplex_rx;
    wire        w_bro_en_rx;
    wire        w_fil_en_rx;
    wire        w_pro_en_rx;
    wire        w_rx_pause_en_rx;
    wire [47:0] w_mac_sa_rx;
    wire [31:0] w_hash_low_rx;
    wire [31:0] w_hash_high_rx;

    eth_sync_level #(
        .WIDTH       (51),
        .RESET_VALUE ({1'b0, 1'b1, 1'b1, 48'd0})
    ) u_sync_tx_cfg (
        .i_dst_clk   (i_mtx_clk),
        .i_dst_rst_n (i_hresetn),
        .i_src_level ({w_tx_en_ahb, w_full_duplex_ahb,
                       w_tx_pause_en_ahb, w_mac_sa_ahb}),
        .o_dst_level (w_tx_cfg_tx)
    );

    assign {w_tx_en_tx, w_full_duplex_tx, w_tx_pause_en_tx,
            w_mac_sa_tx} = w_tx_cfg_tx;

    eth_sync_level #(
        .WIDTH       (1),
        .RESET_VALUE (1'd0)
    ) u_sync_rx_en (
        .i_dst_clk   (i_mrx_clk),
        .i_dst_rst_n (i_hresetn),
        .i_src_level (w_rx_en_ahb),
        .o_dst_level (w_rx_en_sync)
    );

    eth_sync_level #(
        .WIDTH       (117),
        .RESET_VALUE ({1'b1, 1'b0, 1'b0, 1'b0, 1'b1,
                       48'd0, 32'd0, 32'd0})
    ) u_sync_rx_cfg (
        .i_dst_clk   (i_mrx_clk),
        .i_dst_rst_n (i_hresetn),
        .i_src_level ({w_full_duplex_ahb, w_bro_en_ahb,
                       w_fil_en_ahb, w_pro_en_ahb, w_rx_pause_en_ahb,
                       w_mac_sa_ahb, w_hash_low_ahb, w_hash_high_ahb}),
        .o_dst_level (w_rx_cfg_rx)
    );

    reg        r_rx_en_active;

    always @(posedge i_mrx_clk or negedge i_hresetn) begin
        if (!i_hresetn)
            r_rx_en_active <= 1'b0;
        else if (!i_mrxdv)
            r_rx_en_active <= w_rx_en_sync;
    end

    wire        w_rx_en_rx = r_rx_en_active;
    assign {w_full_duplex_rx, w_bro_en_rx, w_fil_en_rx, w_pro_en_rx,
            w_rx_pause_en_rx, w_mac_sa_rx, w_hash_low_rx,
            w_hash_high_rx} = w_rx_cfg_rx;

    //--------------------------------------------------------------------------
    // MII carrier/collision sync into TX clock
    //--------------------------------------------------------------------------
    wire w_tx_will_transmit;
    wire [1:0] w_mii_status_tx;

    eth_sync_level #(
        .WIDTH       (2),
        .RESET_VALUE (128'd0)
    ) u_sync_mii_status_tx (
        .i_dst_clk   (i_mtx_clk),
        .i_dst_rst_n (i_hresetn),
        .i_src_level ({i_mcrs, i_mcoll}),
        .o_dst_level (w_mii_status_tx)
    );

    wire w_tx_carrier_sense = ~w_full_duplex_tx & w_mii_status_tx[1];
    wire w_tx_collision = ~w_full_duplex_tx &
                          w_tx_will_transmit &
                          w_mii_status_tx[0];

    //--------------------------------------------------------------------------
    // TX frame buffer and normal TX byte source
    //--------------------------------------------------------------------------
    wire        w_tx_frame_valid;
    wire [15:0] w_tx_frame_len;
    wire [47:0] w_tx_frame_da;
    wire [9:0]  w_tx_frame_words;
    wire        w_tx_frame_take;
    wire [8:0]  w_tx_buf_rd_addr;
    wire        w_tx_buf_rd_en;
    wire [31:0] w_tx_buf_rd_data;

    wire        w_tx_normal_busy;
    wire        w_tx_normal_done_pulse;
    wire        w_tx_normal_err_pulse;
    wire        w_tx_normal_mac_start;
    wire        w_tx_normal_mac_end;
    wire [7:0]  w_tx_normal_mac_data;
    wire        w_tx_normal_mac_pad_en;
    wire        w_tx_normal_mac_crc_en;
    wire        w_tx_normal_mac_underrun;

    wire        w_mac_tx_done;
    wire        w_mac_tx_retry;
    wire        w_mac_tx_abort;
    wire        w_mac_tx_used_data;

    eth_tx_frame_buffer u_tx_frame_buffer (
        .i_ahb_clk              (i_hclk),
        .i_ahb_rst_n            (i_hresetn),
        .i_tx_en                (w_tx_en_ahb),
        .i_tx_len_wr_en         (w_tx_len_wr_en),
        .i_tx_len               (w_tx_len),
        .i_tx_da                (w_tx_da_ahb),
        .i_tx_payload_wr_en     (w_tx_payload_wr_en),
        .i_tx_payload_wdata     (w_tx_payload_wdata),
        .i_tx_start_pulse       (w_tx_start_pulse),
        .o_ahb_ready            (w_tx_ready_ahb),
        .o_ahb_busy             (w_tx_busy_ahb),
        .o_ahb_sw_err_pulse     (w_tx_sw_err_pulse_ahb),
        .o_ahb_tx_done_pulse    (w_tx_done_pulse_ahb),
        .o_ahb_tx_err_pulse     (w_tx_err_pulse_ahb),
        .i_tx_clk               (i_mtx_clk),
        .i_tx_rst_n             (i_hresetn),
        .o_tx_frame_valid       (w_tx_frame_valid),
        .o_tx_frame_len         (w_tx_frame_len),
        .o_tx_frame_da          (w_tx_frame_da),
        .o_tx_frame_words       (w_tx_frame_words),
        .o_tx_frame_buf         (),
        .i_tx_frame_take        (w_tx_frame_take),
        .o_tx_active            (),
        .i_tx_rd_addr           (w_tx_buf_rd_addr),
        .i_tx_rd_en             (w_tx_buf_rd_en),
        .o_tx_rd_data           (w_tx_buf_rd_data),
        .i_tx_done_pulse        (w_tx_normal_done_pulse),
        .i_tx_err_pulse         (w_tx_normal_err_pulse)
    );

    // Normal TX khong nhan frame moi khi remote PAUSE dang active hoac
    // local PAUSE frame dang doi gui. Frame da bat dau thi duoc gui xong.
    wire w_rx_pause_active_tx;
    wire w_tx_pause_request;
    wire w_tx_pause_active;
    wire w_tx_normal_block = w_rx_pause_active_tx |
                             w_tx_pause_active |
                             w_tx_pause_request;
    wire w_tx_normal_en = w_tx_en_tx &
                          (w_tx_normal_busy | ~w_tx_normal_block);

    eth_tx_buffer_ctrl u_tx_buffer_ctrl (
        .i_clk              (i_mtx_clk),
        .i_rst_n            (i_hresetn),
        .i_tx_en            (w_tx_normal_en),
        .i_mac_sa           (w_mac_sa_tx),
        .i_frame_valid      (w_tx_frame_valid),
        .i_frame_len        (w_tx_frame_len),
        .i_frame_da         (w_tx_frame_da),
        .i_frame_words      (w_tx_frame_words),
        .o_frame_take       (w_tx_frame_take),
        .o_buf_rd_addr      (w_tx_buf_rd_addr),
        .o_buf_rd_en        (w_tx_buf_rd_en),
        .i_buf_rd_data      (w_tx_buf_rd_data),
        .o_tx_done_pulse    (w_tx_normal_done_pulse),
        .o_tx_err_pulse     (w_tx_normal_err_pulse),
        .o_mac_start        (w_tx_normal_mac_start),
        .o_mac_end          (w_tx_normal_mac_end),
        .o_mac_data         (w_tx_normal_mac_data),
        .o_mac_pad_en       (w_tx_normal_mac_pad_en),
        .o_mac_crc_en       (w_tx_normal_mac_crc_en),
        .o_mac_underrun     (w_tx_normal_mac_underrun),
        .i_mac_used_data    (w_mac_tx_used_data),
        .i_mac_retry        (w_mac_tx_retry),
        .i_mac_abort        (w_mac_tx_abort),
        .i_mac_done         (w_mac_tx_done),
        .o_busy             (w_tx_normal_busy)
    );

    //--------------------------------------------------------------------------
    // RX frame buffer, RX MAC and RX buffer parser
    //--------------------------------------------------------------------------
    wire [7:0]  w_rx_mac_data;
    wire        w_rx_mac_valid;
    wire        w_rx_mac_end;
    wire        w_rx_mac_abort;
    wire        w_rx_crc_err;

    wire        w_rx_buf_can_accept;
    wire        w_rx_buf_frame_start;
    wire        w_rx_buf_payload_wr_en;
    wire [31:0] w_rx_buf_payload_wdata;
    wire [1:0]  w_rx_buf_payload_byte_valid;
    wire        w_rx_buf_frame_commit;
    wire        w_rx_buf_frame_drop;
    wire [15:0] w_rx_buf_frame_len;
    wire        w_rx_ctrl_err_pulse_rx;
    wire        w_rx_ctrl_pause_seen_pulse;
    wire [15:0] w_rx_ctrl_pause_time;

    wire        w_rx_frame_busy_pulse_rx;
    wire        w_rx_frame_err_pulse_rx;
    wire        w_rx_pause_req_rx;

    wire w_tx_will_transmit_rx;

    eth_sync_level #(
        .WIDTH       (1),
        .RESET_VALUE (128'd0)
    ) u_sync_tx_active_to_rx (
        .i_dst_clk   (i_mrx_clk),
        .i_dst_rst_n (i_hresetn),
        .i_src_level (w_tx_will_transmit),
        .o_dst_level (w_tx_will_transmit_rx)
    );

    wire w_rx_transmitting = ~w_full_duplex_rx & w_tx_will_transmit_rx;
    wire w_rx_mii_valid = i_mrxdv & w_rx_en_rx;
    wire w_rx_phy_abort = i_mrxerr & i_mrxdv;

    eth_rx_mac u_rx_mac (
        .i_clk             (i_mrx_clk),
        .i_rst_n           (i_hresetn),
        .i_rx_dv           (w_rx_mii_valid),
        .i_rx_data         (i_mrxd),
        .i_rx_en           (w_rx_en_rx),
        .i_transmitting    (w_rx_transmitting),
        .i_pro             (w_pro_en_rx),
        .i_bro             (w_bro_en_rx),
        .i_fil_en          (w_fil_en_rx),
        .i_pass_ctrl       (w_rx_pause_en_rx),
        .i_mac_addr        (w_mac_sa_rx),
        .i_hash0           (w_hash_low_rx),
        .i_hash1           (w_hash_high_rx),
        .i_ctrl_addr_ok    (1'b0),
        .o_rx_data         (w_rx_mac_data),
        .o_rx_valid        (w_rx_mac_valid),
        .o_rx_start        (),
        .o_rx_end          (w_rx_mac_end),
        .o_rx_abort        (w_rx_mac_abort),
        .o_crc_err         (w_rx_crc_err),
        .o_addr_miss       (),
        .o_rx_ready        ()
    );

    eth_rx_buffer_ctrl u_rx_buffer_ctrl (
        .i_clk                    (i_mrx_clk),
        .i_rst_n                  (i_hresetn),
        .i_rx_en                  (w_rx_en_rx),
        .i_rx_pause_en            (w_rx_pause_en_rx),
        .i_rx_valid               (w_rx_mac_valid),
        .i_rx_data                (w_rx_mac_data),
        .i_rx_end                 (w_rx_mac_end),
        .i_rx_abort               (w_rx_mac_abort | w_rx_phy_abort),
        .i_crc_err                (w_rx_crc_err),
        .i_buf_can_accept         (w_rx_buf_can_accept),
        .o_buf_frame_start        (w_rx_buf_frame_start),
        .o_buf_payload_wr_en      (w_rx_buf_payload_wr_en),
        .o_buf_payload_wdata      (w_rx_buf_payload_wdata),
        .o_buf_payload_byte_valid (w_rx_buf_payload_byte_valid),
        .o_buf_frame_commit       (w_rx_buf_frame_commit),
        .o_buf_frame_drop         (w_rx_buf_frame_drop),
        .o_buf_frame_len          (w_rx_buf_frame_len),
        .o_rx_err_pulse           (w_rx_ctrl_err_pulse_rx),
        .o_rx_pause_seen_pulse    (w_rx_ctrl_pause_seen_pulse),
        .o_rx_pause_time          (w_rx_ctrl_pause_time),
        .o_busy                   ()
    );

    eth_rx_frame_buffer u_rx_frame_buffer (
        .i_rx_clk                 (i_mrx_clk),
        .i_rx_rst_n               (i_hresetn),
        .i_rx_en                  (w_rx_en_rx),
        .i_rx_frame_start         (w_rx_buf_frame_start),
        .i_rx_payload_wr_en       (w_rx_buf_payload_wr_en),
        .i_rx_payload_wdata       (w_rx_buf_payload_wdata),
        .i_rx_payload_byte_valid  (w_rx_buf_payload_byte_valid),
        .i_rx_frame_commit        (w_rx_buf_frame_commit),
        .i_rx_frame_drop          (w_rx_buf_frame_drop),
        .i_rx_frame_len           (w_rx_buf_frame_len),
        .o_rx_can_accept          (w_rx_buf_can_accept),
        .o_rx_busy_pulse          (w_rx_frame_busy_pulse_rx),
        .o_rx_err_pulse           (w_rx_frame_err_pulse_rx),
        .o_rx_pause_req           (w_rx_pause_req_rx),
        .i_ahb_clk                (i_hclk),
        .i_ahb_rst_n              (i_hresetn),
        .o_ahb_rx_avail           (w_rx_avail_ahb),
        .o_ahb_rx_len             (w_rx_len_ahb),
        .o_ahb_rx_words           (),
        .i_ahb_rx_rd_en           (w_rx_payload_rd_en),
        .o_ahb_rx_rdata           (w_rx_payload_rdata),
        .i_ahb_rx_release_pulse   (w_rx_release_pulse),
        .o_ahb_sw_err_pulse       (w_rx_sw_err_pulse_ahb)
    );

    //--------------------------------------------------------------------------
    // PAUSE receive timer and PAUSE transmit generator
    //--------------------------------------------------------------------------
    wire w_rx_pause_seen_pulse_rx;
    wire w_tx_pause_mac_start;
    wire w_tx_pause_mac_end;
    wire [7:0] w_tx_pause_mac_data;
    wire w_tx_pause_mac_pad_en;
    wire w_tx_pause_mac_crc_en;
    wire w_tx_pause_mac_underrun;

    eth_rx_pause u_rx_pause (
        .i_rx_clk                 (i_mrx_clk),
        .i_tx_clk                 (i_mtx_clk),
        .i_rst_n                  (i_hresetn),
        .i_rx_pause_en            (w_rx_pause_en_rx),
        .i_pause_seen_rx          (w_rx_ctrl_pause_seen_pulse),
        .i_pause_time_rx          (w_rx_ctrl_pause_time),
        .o_pause_seen_pulse_rx    (w_rx_pause_seen_pulse_rx),
        .o_pause_seen_pulse_tx    (),
        .o_pause_active_tx        (w_rx_pause_active_tx)
    );

    wire w_tx_pause_start = w_tx_en_tx &
                            w_tx_pause_request &
                            ~w_tx_normal_busy &
                            ~w_tx_pause_active;

    eth_tx_pause u_tx_pause (
        .i_clk                    (i_mtx_clk),
        .i_rst_n                  (i_hresetn),
        .i_tx_pause_en            (w_tx_pause_en_tx),
        .i_pause_req_rx           (w_rx_pause_req_rx),
        .i_mac_sa                 (w_mac_sa_tx),
        .i_start                  (w_tx_pause_start),
        .o_pause_req_tx           (),
        .o_pause_request          (w_tx_pause_request),
        .o_active                 (w_tx_pause_active),
        .o_mac_start              (w_tx_pause_mac_start),
        .o_mac_end                (w_tx_pause_mac_end),
        .o_mac_data               (w_tx_pause_mac_data),
        .o_mac_pad_en             (w_tx_pause_mac_pad_en),
        .o_mac_crc_en             (w_tx_pause_mac_crc_en),
        .o_mac_underrun           (w_tx_pause_mac_underrun),
        .i_mac_used_data          (w_mac_tx_used_data),
        .i_mac_done               (w_mac_tx_done),
        .i_mac_retry              (w_mac_tx_retry),
        .i_mac_abort              (w_mac_tx_abort),
        .o_pause_done_pulse       (),
        .o_pause_err_pulse        ()
    );

    //--------------------------------------------------------------------------
    // TX MAC mux: PAUSE has priority when normal TX is idle
    //--------------------------------------------------------------------------
    wire w_tx_pause_sel = w_tx_pause_active | w_tx_pause_start;
    wire w_mac_start = w_tx_pause_sel ? w_tx_pause_mac_start :
                                        w_tx_normal_mac_start;
    wire w_mac_end = w_tx_pause_sel ? w_tx_pause_mac_end :
                                      w_tx_normal_mac_end;
    wire [7:0] w_mac_data = w_tx_pause_sel ? w_tx_pause_mac_data :
                                              w_tx_normal_mac_data;
    wire w_mac_pad_en = w_tx_pause_sel ? w_tx_pause_mac_pad_en :
                                         w_tx_normal_mac_pad_en;
    wire w_mac_crc_en = w_tx_pause_sel ? w_tx_pause_mac_crc_en :
                                         w_tx_normal_mac_crc_en;
    wire w_mac_underrun = w_tx_pause_sel ? w_tx_pause_mac_underrun :
                                           w_tx_normal_mac_underrun;

    eth_tx_mac u_tx_mac (
        .i_clk             (i_mtx_clk),
        .i_rst_n           (i_hresetn),
        .i_tx_start        (w_mac_start),
        .i_tx_end          (w_mac_end),
        .i_tx_underrun     (w_mac_underrun),
        .i_tx_data         (w_mac_data),
        .i_pad_en          (w_mac_pad_en),
        .i_crc_en          (w_mac_crc_en),
        .i_full_duplex     (w_full_duplex_tx),
        .i_carrier_sense   (w_tx_carrier_sense),
        .i_collision       (w_tx_collision),
        .o_mtx_d           (o_mtxd),
        .o_mtx_en          (o_mtxen),
        .o_mtx_err         (o_mtxerr),
        .o_tx_done         (w_mac_tx_done),
        .o_tx_retry        (w_mac_tx_retry),
        .o_tx_abort        (w_mac_tx_abort),
        .o_tx_used_data    (w_mac_tx_used_data),
        .o_defer_ind       (),
        .o_late_collision  (),
        .o_max_collision   (),
        .o_will_transmit   (w_tx_will_transmit)
    );

    //--------------------------------------------------------------------------
    // RX/TX status CDC back to AHB register domain
    //--------------------------------------------------------------------------
    eth_cdc_pulse u_cdc_rx_busy_to_ahb (
        .i_src_clk   (i_mrx_clk),
        .i_src_rst_n (i_hresetn),
        .i_src_pulse (w_rx_frame_busy_pulse_rx),
        .i_dst_clk   (i_hclk),
        .i_dst_rst_n (i_hresetn),
        .o_dst_pulse (w_rx_busy_pulse_ahb)
    );

    eth_cdc_pulse u_cdc_rx_err_to_ahb (
        .i_src_clk   (i_mrx_clk),
        .i_src_rst_n (i_hresetn),
        .i_src_pulse (w_rx_ctrl_err_pulse_rx | w_rx_frame_err_pulse_rx),
        .i_dst_clk   (i_hclk),
        .i_dst_rst_n (i_hresetn),
        .o_dst_pulse (w_rx_err_pulse_ahb)
    );

    eth_cdc_pulse u_cdc_rx_pause_seen_to_ahb (
        .i_src_clk   (i_mrx_clk),
        .i_src_rst_n (i_hresetn),
        .i_src_pulse (w_rx_pause_seen_pulse_rx),
        .i_dst_clk   (i_hclk),
        .i_dst_rst_n (i_hresetn),
        .o_dst_pulse (w_rx_pause_seen_pulse_ahb)
    );

    wire [1:0] w_pause_status_ahb;

    eth_sync_level #(
        .WIDTH       (2),
        .RESET_VALUE (128'd0)
    ) u_sync_pause_status_to_ahb (
        .i_dst_clk   (i_hclk),
        .i_dst_rst_n (i_hresetn),
        .i_src_level ({w_rx_pause_req_rx, w_rx_pause_active_tx}),
        .o_dst_level (w_pause_status_ahb)
    );

    assign w_tx_pause_req_ahb = w_pause_status_ahb[1];
    assign w_rx_pause_active_ahb = w_pause_status_ahb[0];

endmodule
