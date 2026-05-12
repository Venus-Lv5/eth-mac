`timescale 1ns / 1ps

module eth_register (
    input wire                  i_clk,
    input wire                  i_rst_n,

    // From AHB Slave interface
    input wire                  i_rd_en,
    input wire                  i_wr_en,
    input wire [7:0]            i_addr,
    input wire [31:0]           i_wdata,
    output reg  [31:0]          o_rdata,

    // MAC control outputs
    output wire                 o_rx_en,
    output wire                 o_tx_en,
    output wire                 o_bro_en,
    output wire                 o_fil_en,
    output wire                 o_pro_en,
    output wire                 o_full_en,

    // MAC address outputs
    output wire [31:0]          o_mac_addr_low,
    output wire [15:0]          o_mac_addr_high,

    // Hash table outputs
    output wire [31:0]          o_hash_low,
    output wire [31:0]          o_hash_high,

    // Flow control outputs
    output wire                 o_tx_flow_en,
    output wire                 o_rx_flow_en,
    output wire                 o_pass_ctrl,
    output wire                 o_send_pause,
    output wire [15:0]          o_pause_time,

    // Interrupt status signals to Interrupt Controller (from INT_STATUS register)
    output wire                 o_tx_done,
    output wire                 o_tx_err,
    output wire                 o_rx_done,
    output wire                 o_rx_err,
    output wire                 o_rx_busy,
    output wire                 o_tx_ctrl_done,
    output wire                 o_rx_ctrl_done,

    // Interrupt enable signals to Interrupt Controller (from INT_EN register)
    output wire                 o_tx_done_en,
    output wire                 o_tx_err_en,
    output wire                 o_rx_done_en,
    output wire                 o_rx_err_en,
    output wire                 o_rx_busy_en,
    output wire                 o_tx_ctrl_en,
    output wire                 o_rx_ctrl_en,

    // HW clears SEND_PAUSE after PAUSE frame is sent
    input wire                  i_tx_pause_done
);

    // =========================================================
    // REGISTER ADDRESS OFFSETS
    // =========================================================
    localparam bit [9:0] REG0 = 10'd0;
    localparam bit [9:0] REG1 = 10'd1;
    localparam bit [9:0] REG2 = 10'd2;
    localparam bit [9:0] REG3 = 10'd3;
    localparam bit [9:0] REG4 = 10'd4;
    localparam bit [9:0] REG5 = 10'd5;
    localparam bit [9:0] REG6 = 10'd6;
    localparam bit [9:0] REG7 = 10'd8;
    localparam bit [9:0] REG8 = 10'd9;

    // =========================================================
    // DEFAULT VALUES
    // =========================================================
    localparam bit [31:0] DEF0 = 32'h0020;
    localparam bit [31:0] DEF1 = 32'h0;
    localparam bit [31:0] DEF2 = 32'h0;
    localparam bit [31:0] DEF3 = 32'h0;
    localparam bit [31:0] DEF4 = 32'h0;
    localparam bit [31:0] DEF5 = 32'h0;
    localparam bit [31:0] DEF6 = 32'h0;
    localparam bit [31:0] DEF7 = 32'h0;
    localparam bit [31:0] DEF8 = 32'h0;

    // =========================================================
    // ADDRESS DECODE (COMBINATIONAL)
    // =========================================================
    reg [9:0] r_sel;

    always_comb begin
        case (i_addr)
            REG0:  r_sel = 10'd1;
            REG1:  r_sel = 10'd2;
            REG2:  r_sel = 10'd4;
            REG3:  r_sel = 10'd8;
            REG4:  r_sel = 10'd16;
            REG5:  r_sel = 10'd32;
            REG6:  r_sel = 10'd64;
            REG7:  r_sel = 10'd256;
            REG8:  r_sel = 10'd512;
            default: r_sel = 10'd0;
        endcase
    end

    // =========================================================
    // REGISTER DEFINITIONS
    // =========================================================
    reg [31:0] r_mac_ctrl;
    reg [31:0] r_int_status;
    reg [31:0] r_int_en;
    reg [31:0] r_mac_addr_0;
    reg [31:0] r_mac_addr_1;
    reg [31:0] r_hash_0;
    reg [31:0] r_hash_1;
    reg [31:0] r_flow_ctrl;
    reg [31:0] r_tx_flow;

    // =========================================================
    // MAC_CTRL REGISTER (0x00)
    // =========================================================
    // bit[0]: RX_EN   - Enable receiver
    // bit[1]: TX_EN   - Enable transmitter
    // bit[2]: BRO     - Enable broadcast reception
    // bit[3]: FIL_EN  - Enable multicast hash filter
    // bit[4]: PRO     - Enable promiscuous mode
    // bit[5]: FULL    - Full duplex (default 1)
    // bit[31:6]: Reserved
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_ctrl <= DEF0;
        else if (i_wr_en && r_sel[0])
            r_mac_ctrl[5:0] <= i_wdata[5:0];
    end

    assign o_rx_en      = r_mac_ctrl[0];
    assign o_tx_en      = r_mac_ctrl[1];
    assign o_bro_en     = r_mac_ctrl[2];
    assign o_fil_en     = r_mac_ctrl[3];
    assign o_pro_en     = r_mac_ctrl[4];
    assign o_full_en    = r_mac_ctrl[5];

    // =========================================================
    // INT_STATUS REGISTER (0x04) - R/W1C
    // =========================================================
    // bit[0]: TX_DONE       - Transmit complete
    // bit[1]: TX_ERR        - Transmit error
    // bit[2]: RX_DONE       - Receive complete
    // bit[3]: RX_ERR        - Receive error
    // bit[4]: RX_BUSY       - RX buffer unavailable
    // bit[5]: TX_CTRL_DONE  - TX control frame complete
    // bit[6]: RX_CTRL_DONE  - RX control frame complete
    // bit[31:7]: Reserved
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_int_status <= DEF1;
        else if (i_wr_en && r_sel[1]) begin
            if (i_wdata[0]) r_int_status[0] <= 1'b0;
            if (i_wdata[1]) r_int_status[1] <= 1'b0;
            if (i_wdata[2]) r_int_status[2] <= 1'b0;
            if (i_wdata[3]) r_int_status[3] <= 1'b0;
            if (i_wdata[4]) r_int_status[4] <= 1'b0;
            if (i_wdata[5]) r_int_status[5] <= 1'b0;
            if (i_wdata[6]) r_int_status[6] <= 1'b0;
        end
    end

    // =========================================================
    // INT_EN REGISTER (0x08)
    // =========================================================
    // bit[0]: TX_DONE_EN    - Enable TX_DONE interrupt
    // bit[1]: TX_ERR_EN     - Enable TX_ERR interrupt
    // bit[2]: RX_DONE_EN    - Enable RX_DONE interrupt
    // bit[3]: RX_ERR_EN     - Enable RX_ERR interrupt
    // bit[4]: RX_BUSY_EN    - Enable RX_BUSY interrupt
    // bit[5]: TX_CTRL_EN    - Enable TX control frame interrupt
    // bit[6]: RX_CTRL_EN    - Enable RX control frame interrupt
    // bit[31:7]: Reserved
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_int_en <= DEF2;
        else if (i_wr_en && r_sel[2])
            r_int_en[6:0] <= i_wdata[6:0];
    end

    // =========================================================
    // MAC_ADDR_0 REGISTER (0x0C) - Lower 32 bits of MAC address
    // =========================================================
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_addr_0 <= DEF3;
        else if (i_wr_en && r_sel[3])
            r_mac_addr_0 <= i_wdata;
    end

    assign o_mac_addr_low = r_mac_addr_0;

    // =========================================================
    // MAC_ADDR_1 REGISTER (0x10) - Upper 16 bits of MAC address
    // =========================================================
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_mac_addr_1 <= DEF4;
        else if (i_wr_en && r_sel[4])
            r_mac_addr_1[15:0] <= i_wdata[15:0];
    end

    assign o_mac_addr_high = r_mac_addr_1[15:0];

    // =========================================================
    // HASH_0 REGISTER (0x14) - Lower 32 bits of multicast hash
    // =========================================================
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_hash_0 <= DEF5;
        else if (i_wr_en && r_sel[5])
            r_hash_0 <= i_wdata;
    end

    assign o_hash_low = r_hash_0;

    // =========================================================
    // HASH_1 REGISTER (0x18) - Upper 32 bits of multicast hash
    // =========================================================
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_hash_1 <= DEF6;
        else if (i_wr_en && r_sel[6])
            r_hash_1 <= i_wdata;
    end

    assign o_hash_high = r_hash_1;

    // =========================================================
    // FLOW_CTRL REGISTER (0x20)
    // =========================================================
    // bit[0]: TX_FLOW_EN - Enable TX PAUSE frame generation
    // bit[1]: RX_FLOW_EN - Enable RX PAUSE frame handling
    // bit[2]: PASS_CTRL  - Forward control frames to host
    // bit[31:3]: Reserved
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_flow_ctrl <= DEF7;
        else if (i_wr_en && r_sel[8])
            r_flow_ctrl[2:0] <= i_wdata[2:0];
    end

    assign o_tx_flow_en = r_flow_ctrl[0];
    assign o_rx_flow_en = r_flow_ctrl[1];
    assign o_pass_ctrl  = r_flow_ctrl[2];

    // =========================================================
    // TX_FLOW REGISTER (0x24) - TX PAUSE frame control
    // =========================================================
    // bit[0]:   SEND_PAUSE  - RW/SC, HW clears after PAUSE sent
    // bit[16:1]: PAUSE_TIME - Pause time value
    // bit[31:17]: Reserved
    always @(posedge i_clk, negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_flow <= DEF8;
        else if (i_wr_en && r_sel[9])
            r_tx_flow[16:0] <= {i_wdata[16:1], 1'b0};
        else if (i_tx_pause_done)
            r_tx_flow[0] <= 1'b0;
    end

    assign o_send_pause = r_tx_flow[0];
    assign o_pause_time = r_tx_flow[16:1];

    // =========================================================
    // INTERRUPT SIGNALS OUTPUT TO INTERRUPT CONTROLLER
    // =========================================================
    // INT_STATUS bits
    assign o_tx_done      = r_int_status[0];
    assign o_tx_err       = r_int_status[1];
    assign o_rx_done      = r_int_status[2];
    assign o_rx_err       = r_int_status[3];
    assign o_rx_busy      = r_int_status[4];
    assign o_tx_ctrl_done = r_int_status[5];
    assign o_rx_ctrl_done = r_int_status[6];

    // INT_EN bits
    assign o_tx_done_en   = r_int_en[0];
    assign o_tx_err_en   = r_int_en[1];
    assign o_rx_done_en  = r_int_en[2];
    assign o_rx_err_en   = r_int_en[3];
    assign o_rx_busy_en  = r_int_en[4];
    assign o_tx_ctrl_en  = r_int_en[5];
    assign o_rx_ctrl_en  = r_int_en[6];

    // =========================================================
    // READ LOGIC (COMBINATIONAL)
    // =========================================================
    always_comb begin
        if (i_rd_en)
            case (r_sel)
                10'd1:   o_rdata = r_mac_ctrl;
                10'd2:   o_rdata = r_int_status;
                10'd4:   o_rdata = r_int_en;
                10'd8:   o_rdata = r_mac_addr_0;
                10'd16:  o_rdata = r_mac_addr_1;
                10'd32:  o_rdata = r_hash_0;
                10'd64:  o_rdata = r_hash_1;
                10'd256: o_rdata = r_flow_ctrl;
                10'd512: o_rdata = r_tx_flow;
                default:  o_rdata = 32'h0;
            endcase
        else
            o_rdata = 32'h0;
    end

endmodule
