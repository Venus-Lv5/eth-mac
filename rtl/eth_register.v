`timescale 1ns/1ps

//------------------------------------------------------------------------------
// Khoi thanh ghi Ethernet MAC buffer-based
//
// i_addr la dia chi word tu eth_ahb_slave: byte_addr[9:2].
//
// Bang thanh ghi:
//   0x00 MAC_SA_LOW     RW
//   0x04 MAC_SA_HIGH    RW, chi dung [15:0]
//   0x08 PAUSE_CTRL     RW
//   0x0C IER            RW
//   0x10 MAC_CTRL       RW
//   0x20 HASH_0         RW
//   0x24 HASH_1         RW
//   0x40 TX_DA_LOW      RW
//   0x44 TX_DA_HIGH     RW, chi dung [15:0]
//   0x48 TX_LEN         RW
//   0x4C TX_DATA        WO
//   0x50 TX_CMD         WO
//   0x60 FSR            RO/W1C
//   0x64 RX_LEN         RO
//   0x68 RX_DATA        RO
//   0x6C RX_CMD         WO
//   Dia chi khong liet ke trong 0x00..0xFF la RSVD
//------------------------------------------------------------------------------
module eth_register (
    input  wire        i_clk,
    input  wire        i_rst_n,

    input  wire        i_rd_en,
    input  wire        i_wr_en,
    input  wire [7:0]  i_addr,
    input  wire [31:0] i_wdata,
    output reg  [31:0] o_rdata,
    output wire        o_reg_error,

    // Cau hinh MAC.
    output wire        o_rx_en,
    output wire        o_tx_en,
    output wire        o_bro_en,
    output wire        o_fil_en,
    output wire        o_pro_en,
    output wire        o_full_duplex,
    output wire [47:0] o_tx_da,
    output wire [47:0] o_mac_sa,
    output wire [31:0] o_hash_low,
    output wire [31:0] o_hash_high,

    // Duong TX frame buffer trong clock AHB.
    output wire        o_tx_len_wr_en,
    output wire [15:0] o_tx_len,
    output wire        o_tx_payload_wr_en,
    output wire [31:0] o_tx_payload_wdata,
    output wire        o_tx_start_pulse,
    input  wire        i_tx_ready,
    input  wire        i_tx_busy,
    input  wire        i_tx_sw_err_pulse,

    // Duong RX frame buffer trong clock AHB.
    output wire        o_rx_payload_rd_en,
    input  wire [31:0] i_rx_payload_rdata,
    input  wire        i_rx_avail,
    input  wire [15:0] i_rx_len,
    output wire        o_rx_release_pulse,
    input  wire        i_rx_sw_err_pulse,

    // Tin hieu trang thai. Cac pulse/status nay phai o clock i_clk.
    input  wire        i_tx_done_pulse,
    input  wire        i_tx_err_pulse,

    input  wire        i_rx_busy_pulse,
    input  wire        i_rx_err_pulse,

    // Trang thai/dieu khien PAUSE.
    input  wire        i_tx_pause_req,
    input  wire        i_rx_pause_active,
    input  wire        i_rx_pause_seen_pulse,
    output wire        o_tx_pause_en,
    output wire        o_rx_pause_en,

    output wire [5:0]  o_int_en,
    output wire        o_irq
);

    //--------------------------------------------------------------------------
    // Giai ma dia chi
    //--------------------------------------------------------------------------
    localparam [7:0] REG_MAC_SA_LOW  = 8'h00; // byte 0x00
    localparam [7:0] REG_MAC_SA_HIGH = 8'h01; // byte 0x04
    localparam [7:0] REG_PAUSE_CTRL  = 8'h02; // byte 0x08
    localparam [7:0] REG_IER         = 8'h03; // byte 0x0C
    localparam [7:0] REG_MAC_CTRL    = 8'h04; // byte 0x10
    localparam [7:0] REG_HASH_0      = 8'h08; // byte 0x20
    localparam [7:0] REG_HASH_1      = 8'h09; // byte 0x24
    localparam [7:0] REG_TX_DA_LOW   = 8'h10; // byte 0x40
    localparam [7:0] REG_TX_DA_HIGH  = 8'h11; // byte 0x44
    localparam [7:0] REG_TX_LEN      = 8'h12; // byte 0x48
    localparam [7:0] REG_TX_DATA     = 8'h13; // byte 0x4C
    localparam [7:0] REG_TX_CMD      = 8'h14; // byte 0x50
    localparam [7:0] REG_FSR         = 8'h18; // byte 0x60
    localparam [7:0] REG_RX_LEN      = 8'h19; // byte 0x64
    localparam [7:0] REG_RX_DATA     = 8'h1A; // byte 0x68
    localparam [7:0] REG_RX_CMD      = 8'h1B; // byte 0x6C

    localparam [15:0] MAX_PAYLOAD_BYTES = 16'd1500;

    wire w_sel_mac_ctrl    = (i_addr == REG_MAC_CTRL);
    wire w_sel_ier         = (i_addr == REG_IER);
    wire w_sel_fsr         = (i_addr == REG_FSR);
    wire w_sel_tx_da_low   = (i_addr == REG_TX_DA_LOW);
    wire w_sel_tx_da_high  = (i_addr == REG_TX_DA_HIGH);
    wire w_sel_mac_sa_low  = (i_addr == REG_MAC_SA_LOW);
    wire w_sel_mac_sa_high = (i_addr == REG_MAC_SA_HIGH);
    wire w_sel_tx_len      = (i_addr == REG_TX_LEN);
    wire w_sel_tx_data     = (i_addr == REG_TX_DATA);
    wire w_sel_rx_data     = (i_addr == REG_RX_DATA);
    wire w_sel_tx_cmd      = (i_addr == REG_TX_CMD);
    wire w_sel_rx_cmd      = (i_addr == REG_RX_CMD);
    wire w_sel_hash_0      = (i_addr == REG_HASH_0);
    wire w_sel_hash_1      = (i_addr == REG_HASH_1);
    wire w_sel_pause_ctrl  = (i_addr == REG_PAUSE_CTRL);

    wire w_wr_mac_ctrl    = i_wr_en & w_sel_mac_ctrl;
    wire w_wr_ier         = i_wr_en & w_sel_ier;
    wire w_wr_fsr         = i_wr_en & w_sel_fsr;
    wire w_wr_tx_da_low   = i_wr_en & w_sel_tx_da_low;
    wire w_wr_tx_da_high  = i_wr_en & w_sel_tx_da_high;
    wire w_wr_mac_sa_low  = i_wr_en & w_sel_mac_sa_low;
    wire w_wr_mac_sa_high = i_wr_en & w_sel_mac_sa_high;
    wire w_wr_tx_len      = i_wr_en & w_sel_tx_len;
    wire w_wr_tx_data     = i_wr_en & w_sel_tx_data;
    wire w_wr_tx_cmd      = i_wr_en & w_sel_tx_cmd;
    wire w_wr_rx_cmd      = i_wr_en & w_sel_rx_cmd;
    wire w_wr_hash_0      = i_wr_en & w_sel_hash_0;
    wire w_wr_hash_1      = i_wr_en & w_sel_hash_1;
    wire w_wr_pause_ctrl  = i_wr_en & w_sel_pause_ctrl;

    wire w_rd_rx_data     = i_rd_en & w_sel_rx_data;

    //--------------------------------------------------------------------------
    // Cac thanh ghi cau hinh
    //--------------------------------------------------------------------------
    reg [31:0] r_mac_ctrl;
    reg [31:0] r_ier;
    reg [31:0] r_tx_da_low;
    reg [31:0] r_tx_da_high;
    reg [31:0] r_mac_sa_low;
    reg [31:0] r_mac_sa_high;
    reg [31:0] r_hash_0;
    reg [31:0] r_hash_1;
    reg [1:0]  r_pause_en;
    reg        r_fsr_rx_pause_seen;
    reg [15:0] r_tx_len;

    // MAC_CTRL:
    //   bit[0] RX_EN
    //   bit[1] TX_EN
    //   bit[2] BRO
    //   bit[3] FIL_EN
    //   bit[4] PRO
    //   bit[5] FULL, gia tri reset la 1
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_ctrl <= 32'h0000_0020;
        else if (w_wr_mac_ctrl)
            r_mac_ctrl[5:0] <= i_wdata[5:0];
    end

    assign o_rx_en       = r_mac_ctrl[0];
    assign o_tx_en       = r_mac_ctrl[1];
    assign o_bro_en      = r_mac_ctrl[2];
    assign o_fil_en      = r_mac_ctrl[3];
    assign o_pro_en      = r_mac_ctrl[4];
    assign o_full_duplex = r_mac_ctrl[5];

    // IER:
    //   bit[0] cho phep interrupt TX_DONE
    //   bit[1] cho phep interrupt TX_ERR
    //   bit[2] cho phep interrupt RX_AVAIL
    //   bit[3] cho phep interrupt RX_BUSY
    //   bit[4] cho phep interrupt RX_ERR
    //   bit[5] cho phep interrupt RX_PAUSE_SEEN
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_ier <= 32'h0000_0000;
        else if (w_wr_ier)
            r_ier[5:0] <= i_wdata[5:0];
    end

    assign o_int_en = r_ier[5:0];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_da_low <= 32'h0000_0000;
        else if (w_wr_tx_da_low)
            r_tx_da_low <= i_wdata;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_da_high <= 32'h0000_0000;
        else if (w_wr_tx_da_high)
            r_tx_da_high <= {16'h0000, i_wdata[15:0]};
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_sa_low <= 32'h0000_0000;
        else if (w_wr_mac_sa_low)
            r_mac_sa_low <= i_wdata;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_sa_high <= 32'h0000_0000;
        else if (w_wr_mac_sa_high)
            r_mac_sa_high <= {16'h0000, i_wdata[15:0]};
    end

    assign o_tx_da  = {r_tx_da_high[15:0], r_tx_da_low};
    assign o_mac_sa = {r_mac_sa_high[15:0], r_mac_sa_low};

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_hash_0 <= 32'h0000_0000;
        else if (w_wr_hash_0)
            r_hash_0 <= i_wdata;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_hash_1 <= 32'h0000_0000;
        else if (w_wr_hash_1)
            r_hash_1 <= i_wdata;
    end

    assign o_hash_low  = r_hash_0;
    assign o_hash_high = r_hash_1;

    // PAUSE_CTRL:
    //   bit[0] TX_PAUSE_EN, RW, reset 1
    //   bit[1] RX_PAUSE_EN, RW, reset 1
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_pause_en <= 2'b11;
        end else begin
            if (w_wr_pause_ctrl)
                r_pause_en <= i_wdata[1:0];
        end
    end

    assign o_tx_pause_en = r_pause_en[0];
    assign o_rx_pause_en = r_pause_en[1];

    //--------------------------------------------------------------------------
    // Duong TX frame buffer
    //--------------------------------------------------------------------------
    wire w_tx_len_valid = (i_wdata[15:0] <= MAX_PAYLOAD_BYTES);
    wire w_tx_len_overflow_wr = w_wr_tx_len & ~w_tx_len_valid;
    wire w_tx_len_write = w_wr_tx_len & w_tx_len_valid & i_tx_ready;
    wire w_tx_bad_len_wr = w_wr_tx_len & ~w_tx_len_write;

    // Register block chi decode access va giu ban sao TX_LEN de CPU doc lai.
    // Frame buffer se kiem tra thu tu TX_LEN/TX_DATA/TX_START va bao loi qua
    // i_tx_sw_err_pulse neu CPU truy cap sai trang thai.
    assign o_tx_len_wr_en      = w_tx_len_write;
    assign o_tx_payload_wr_en  = w_wr_tx_data;
    assign o_tx_payload_wdata = i_wdata;
    assign o_tx_len = w_tx_len_write ? i_wdata[15:0] : r_tx_len;
    assign o_tx_start_pulse = w_wr_tx_cmd & i_wdata[0];
    assign o_reg_error = w_tx_len_overflow_wr;

    wire w_sw_tx_err = w_tx_bad_len_wr | i_tx_sw_err_pulse;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_len <= 16'd0;
        else if (w_tx_len_write)
            r_tx_len <= i_wdata[15:0];
    end

    //--------------------------------------------------------------------------
    // Duong RX frame buffer
    //--------------------------------------------------------------------------
    // Frame buffer se kiem tra doc/release dung so word. Register chi tao
    // request tu access cua CPU.
    assign o_rx_payload_rd_en = w_rd_rx_data;
    assign o_rx_release_pulse = w_wr_rx_cmd & i_wdata[0];

    wire w_sw_rx_err = i_rx_sw_err_pulse;

    //--------------------------------------------------------------------------
    // FSR:
    //   bit[0] TX_READY   RO
    //   bit[1] TX_BUSY    RO
    //   bit[2] TX_DONE    W1C
    //   bit[3] TX_ERR     W1C
    //   bit[4] RX_AVAIL   RO
    //   bit[5] RX_BUSY    W1C
    //   bit[6] RX_ERR     W1C
    //   bit[7] TX_PAUSE_REQ    RO
    //   bit[8] RX_PAUSE_ACTIVE RO
    //   bit[9] RX_PAUSE_SEEN   W1C
    //--------------------------------------------------------------------------
    reg r_fsr_tx_done;
    reg r_fsr_tx_err;
    reg r_fsr_rx_busy;
    reg r_fsr_rx_err;

    wire w_fsr_tx_done_set = i_tx_done_pulse;
    wire w_fsr_tx_err_set  = i_tx_err_pulse | w_sw_tx_err;
    wire w_fsr_rx_busy_set = i_rx_busy_pulse;
    wire w_fsr_rx_err_set  = i_rx_err_pulse | w_sw_rx_err;

    // Chinh sach W1C: software clear duoc xu ly truoc, sau do hardware set
    // thang neu cung chu ky. Nhu vay khong mat event moi khi firmware dang
    // clear event cu.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_fsr_tx_done <= 1'b0;
            r_fsr_tx_err  <= 1'b0;
            r_fsr_rx_busy <= 1'b0;
            r_fsr_rx_err  <= 1'b0;
            r_fsr_rx_pause_seen <= 1'b0;
        end else begin
            if (w_wr_fsr) begin
                if (i_wdata[2])
                    r_fsr_tx_done <= 1'b0;
                if (i_wdata[3])
                    r_fsr_tx_err <= 1'b0;
                if (i_wdata[5])
                    r_fsr_rx_busy <= 1'b0;
                if (i_wdata[6])
                    r_fsr_rx_err <= 1'b0;
                if (i_wdata[9])
                    r_fsr_rx_pause_seen <= 1'b0;
            end

            if (w_fsr_tx_done_set)
                r_fsr_tx_done <= 1'b1;
            if (w_fsr_tx_err_set)
                r_fsr_tx_err <= 1'b1;
            if (w_fsr_rx_busy_set)
                r_fsr_rx_busy <= 1'b1;
            if (w_fsr_rx_err_set)
                r_fsr_rx_err <= 1'b1;
            if (i_rx_pause_seen_pulse)
                r_fsr_rx_pause_seen <= 1'b1;
        end
    end

    wire [31:0] w_fsr = {
        22'd0,
        r_fsr_rx_pause_seen,
        i_rx_pause_active,
        i_tx_pause_req,
        r_fsr_rx_err,
        r_fsr_rx_busy,
        i_rx_avail,
        r_fsr_tx_err,
        r_fsr_tx_done,
        i_tx_busy,
        i_tx_ready
    };

    wire [31:0] w_pause_ctrl = {
        30'd0,
        r_pause_en
    };

    assign o_irq = (r_ier[0] & r_fsr_tx_done) |
                   (r_ier[1] & r_fsr_tx_err)  |
                   (r_ier[2] & i_rx_avail)    |
                   (r_ier[3] & r_fsr_rx_busy) |
                   (r_ier[4] & r_fsr_rx_err)  |
                   (r_ier[5] & r_fsr_rx_pause_seen);

    //--------------------------------------------------------------------------
    // Mux du lieu doc
    //--------------------------------------------------------------------------
    always @(*) begin
        if (i_rd_en) begin
            case (i_addr)
                REG_MAC_CTRL:
                    o_rdata = {26'd0, r_mac_ctrl[5:0]};
                REG_IER:
                    o_rdata = {26'd0, r_ier[5:0]};
                REG_FSR:
                    o_rdata = w_fsr;
                REG_TX_DA_LOW:
                    o_rdata = r_tx_da_low;
                REG_TX_DA_HIGH:
                    o_rdata = r_tx_da_high;
                REG_MAC_SA_LOW:
                    o_rdata = r_mac_sa_low;
                REG_MAC_SA_HIGH:
                    o_rdata = r_mac_sa_high;
                REG_TX_LEN:
                    o_rdata = {16'd0, r_tx_len};
                REG_RX_LEN:
                    o_rdata = {16'd0, i_rx_len};
                REG_RX_DATA:
                    o_rdata = i_rx_payload_rdata;
                REG_HASH_0:
                    o_rdata = r_hash_0;
                REG_HASH_1:
                    o_rdata = r_hash_1;
                REG_PAUSE_CTRL:
                    o_rdata = w_pause_ctrl;
                default:
                    o_rdata = 32'h0000_0000;
            endcase
        end else begin
            o_rdata = 32'h0000_0000;
        end
    end

endmodule
