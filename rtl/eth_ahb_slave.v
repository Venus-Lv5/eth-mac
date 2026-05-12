`timescale 1ns/1ps

module eth_ahb_slave
#(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)
(
    input wire                  i_HCLK,
    input wire                  i_HRESET_n,

    input wire [ADDR_WIDTH-1:0] i_HADDR,
    input wire [1:0]            i_HTRANS,
    input wire                  i_HWRITE,
    input wire [2:0]            i_HSIZE,
    input wire [2:0]            i_HBURST,
    input wire [DATA_WIDTH-1:0] i_HWDATA,

    input wire                  i_HSEL,
    input wire                  i_HREADY,

    output reg  [DATA_WIDTH-1:0] o_HRDATA,
    output reg                  o_HREADYOUT,
    output reg                  o_HRESP,

    // REG interface
    output reg                  o_reg_wr_en,
    output reg                  o_reg_rd_en,
    output reg [ADDR_WIDTH-1:0] o_reg_addr,
    output reg [DATA_WIDTH-1:0] o_reg_wdata,

    // BD interface
    output reg                  o_bd_wr_en,
    output reg                  o_bd_rd_en,
    output reg [ADDR_WIDTH-1:0] o_bd_addr,
    output reg [DATA_WIDTH-1:0] o_bd_wdata,

    // read data
    input wire [DATA_WIDTH-1:0] i_reg_rdata,
    input wire [DATA_WIDTH-1:0] i_bd_rdata
);

    // =========================================================
    // AHB-Lite No-Wait-State Slave with Error Handling
    //
    // Protocol:
    // - Valid access:   HREADYOUT=1, HRESP=0  (no wait state)
    // - Invalid access:  2-cycle ERROR response
    //   Cycle 1: HREADYOUT=0, HRESP=1
    //   Cycle 2: HREADYOUT=1, HRESP=1 (slave done)
    // =========================================================

    localparam HRESP_OKAY  = 1'b0;
    localparam HRESP_ERROR = 1'b1;

    // =========================================================
    // AHB TRANS TYPE
    // =========================================================
    localparam TRANS_IDLE   = 2'b00;
    localparam TRANS_NONSEQ = 2'b10;
    localparam TRANS_SEQ    = 2'b11;

    wire w_trans_valid = i_HSEL & i_HREADY &
                        (i_HTRANS == TRANS_NONSEQ || i_HTRANS == TRANS_SEQ);

    // =========================================================
    // ADDRESS PHASE REGISTER
    // =========================================================
    reg [ADDR_WIDTH-1:0] r_addr;
    reg                  r_wr;
    reg                  r_valid;

    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n) begin
            r_addr  <= 0;
            r_wr    <= 0;
            r_valid <= 0;
        end
        else if (i_HREADY) begin
            r_addr  <= i_HADDR;
            r_wr    <= i_HWRITE;
            r_valid <= w_trans_valid;
        end
    end

    // =========================================================
    // DATA PHASE REGISTER
    // =========================================================
    reg [DATA_WIDTH-1:0] r_wdata;

    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n)
            r_wdata <= 0;
        else if (i_HREADY)
            r_wdata <= i_HWDATA;
    end

    // =========================================================
    // ADDRESS DECODE (at data phase)
    // =========================================================
    wire w_reg_access = r_valid && (r_addr[9:8] == 2'b00);
    wire w_bd_access  = r_valid && (r_addr[9:8] == 2'b01);
    wire w_invalid    = r_valid && (r_addr[9:8] != 2'b00) && (r_addr[9:8] != 2'b01);

    // =========================================================
    // CONTROL SIGNALS
    // =========================================================
    wire w_reg_wr = w_reg_access &  r_wr;
    wire w_reg_rd = w_reg_access & ~r_wr;
    wire w_bd_wr  = w_bd_access  &  r_wr;
    wire w_bd_rd  = w_bd_access  & ~r_wr;

    // =========================================================
    // SLAVE OUTPUTS (registered on data phase)
    // =========================================================
    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n) begin
            o_reg_wr_en <= 0;
            o_reg_rd_en <= 0;
            o_reg_addr  <= 0;
            o_reg_wdata <= 0;

            o_bd_wr_en  <= 0;
            o_bd_rd_en  <= 0;
            o_bd_addr   <= 0;
            o_bd_wdata  <= 0;
        end
        else if (i_HREADY) begin
            // Only drive REG/BD signals for valid accesses
            o_reg_wr_en <= w_reg_wr;
            o_reg_rd_en <= w_reg_rd;
            o_reg_addr  <= r_addr[9:2];
            o_reg_wdata <= r_wdata;

            o_bd_wr_en  <= w_bd_wr;
            o_bd_rd_en  <= w_bd_rd;
            o_bd_addr   <= (r_addr - 10'h400) >> 2;
            o_bd_wdata  <= r_wdata;
        end
    end

    // =========================================================
    // READ DATA MUX
    // =========================================================
    wire [DATA_WIDTH-1:0] w_read_mux =
        w_reg_access ? i_reg_rdata :
        w_bd_access  ? i_bd_rdata  :
        32'h0;

    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n)
            o_HRDATA <= 0;
        else if (i_HREADY)
            o_HRDATA <= w_read_mux;
    end

    // =========================================================
    // ERROR STATE MACHINE
    // 2-cycle ERROR response for invalid addresses
    // =========================================================
    localparam ERR_IDLE  = 2'b00;
    localparam ERR_FIRST = 2'b01;  // Cycle 1: HRESP=ERROR, HREADY=0
    localparam ERR_LAST  = 2'b10;  // Cycle 2: HRESP=ERROR, HREADY=1

    reg [1:0] r_err_state;

    always @(posedge i_HCLK or negedge i_HRESET_n) begin
        if (!i_HRESET_n) begin
            r_err_state  <= ERR_IDLE;
            o_HREADYOUT  <= 1'b1;
            o_HRESP      <= HRESP_OKAY;
        end else begin
            case (r_err_state)
                ERR_IDLE: begin
                    if (w_invalid) begin
                        r_err_state  <= ERR_FIRST;
                        o_HREADYOUT  <= 1'b0;  // Insert 1 wait state
                        o_HRESP      <= HRESP_ERROR;
                    end else begin
                        o_HREADYOUT  <= 1'b1;
                        o_HRESP      <= HRESP_OKAY;
                    end
                end

                ERR_FIRST: begin
                    // Cycle 1 of ERROR, host must wait
                    r_err_state  <= ERR_LAST;
                    o_HREADYOUT  <= 1'b1;  // Now ready
                    o_HRESP      <= HRESP_ERROR;
                end

                ERR_LAST: begin
                    // Cycle 2: ERROR done, return to idle
                    r_err_state  <= ERR_IDLE;
                    o_HREADYOUT  <= 1'b1;
                    o_HRESP      <= HRESP_OKAY;
                end

                default: begin
                    r_err_state  <= ERR_IDLE;
                    o_HREADYOUT  <= 1'b1;
                    o_HRESP      <= HRESP_OKAY;
                end
            endcase
        end
    end

endmodule
