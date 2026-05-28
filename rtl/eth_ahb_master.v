`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////
////  eth_ahb_master.v                                             ////
////                                                              ////
////  AHB-Lite Master for Ethernet MAC DMA                         ////
////  - No-wait-state slave assumption                             ////
////  - TX: burst read from system RAM                            ////
////  - RX: burst write to system RAM                             ////
////  - TX priority > RX                                          ////
//////////////////////////////////////////////////////////////////////

module eth_ahb_master #(
    parameter BURST_LENGTH       = 4,
    parameter BURST_CNT_WIDTH   = 4
) (
    // System
    input wire                  i_clk,
    input wire                  i_rst_n,

    // AHB-Lite Master Port
    output reg  [31:0]          o_haddr,
    output reg  [2:0]           o_hburst,
    output wire                 o_hmastlock,
    output wire [3:0]           o_hprot,
    output reg  [2:0]           o_hsize,
    output reg  [1:0]           o_htrans,
    output reg  [31:0]          o_hwdata,
    output reg                  o_hwrite,
    output reg                  o_hsel,      // Single select (AHB-Lite)
    input wire  [31:0]          i_hrdata,
    input wire                  i_hready,    // Slave ready
    input wire                  i_hresp,     // Slave response

    // TX DMA Interface - read from system RAM
    input wire                  i_tx_req,
    input wire [31:2]           i_tx_addr,
    input wire [1:0]            i_tx_addr_lsb,   // byte offset for unaligned buffers
    input wire [15:0]           i_tx_len,
    input wire                  i_tx_burst_en,
    output reg                  o_tx_ack,
    output reg  [31:0]          o_tx_rdata,
    output reg                  o_tx_err,
    output reg                  o_tx_ptr_inc,

    // RX DMA Interface - write to system RAM
    input wire                  i_rx_req,
    input wire [31:2]           i_rx_addr,
    input wire [1:0]            i_rx_addr_lsb,  // byte offset for unaligned buffers
    input wire [15:0]           i_rx_len,       // transfer length
    input wire [31:0]           i_rx_wdata,
    input wire                  i_rx_burst_en,
    output reg                  o_rx_ack,
    output reg                  o_rx_err,
    output reg                  o_rx_ptr_inc,

    // Control
    input wire                  i_tx_en,
    input wire                  i_rx_en
);

    // =========================================================
    // Local Parameters
    // =========================================================
    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_NONSEQ  = 2'b10;
    localparam HTRANS_SEQ     = 2'b11;

    localparam HBURST_SINGLE = 3'b000;
    localparam HBURST_INCR4  = 3'b011;
    localparam HBURST_INCR8  = 3'b101;
    localparam HBURST_INCR16 = 3'b111;

    localparam HSIZE_WORD    = 3'b010;

    localparam HRESP_OKAY    = 1'b0;
    localparam HRESP_ERROR   = 1'b1;

    localparam HBURST_TYPE = (BURST_LENGTH == 4)  ? HBURST_INCR4  :
                             (BURST_LENGTH == 8)  ? HBURST_INCR8  :
                             (BURST_LENGTH == 16) ? HBURST_INCR16 :
                                                    HBURST_SINGLE;

    // =========================================================
    // FSM States
    // =========================================================
    localparam S_IDLE = 2'b00;
    localparam S_TX   = 2'b01;  // TX master active (read from RAM)
    localparam S_RX   = 2'b10;  // RX master active (write to RAM)
    localparam S_ERR  = 2'b11;  // Waiting through ERROR cycle

    reg [1:0] r_state;
    reg [1:0] r_next;

    // =========================================================
    // Burst control
    // =========================================================
    reg [BURST_CNT_WIDTH-1:0] r_burst_cnt;
    reg r_burst_en;
    reg r_burst_last;

    // =========================================================
    // Length tracking
    // =========================================================
    reg [31:2]      r_tx_addr;
    reg [31:2]      r_rx_addr;
    reg [15:0]      r_tx_len;
    reg [15:0]      r_rx_len;
    reg [1:0]       r_tx_lsb_rst;  // byte offset latch for unaligned buffers

    wire w_len_eq0 = (r_tx_len == 16'd0);
    wire w_len_lt4 = (r_tx_len < 16'd4);
    wire w_rx_len_eq0 = (r_rx_len == 16'd0);
    wire w_rx_len_lt4 = (r_rx_len < 16'd4);

    // =========================================================
    // Request arbitration
    // =========================================================
    wire w_tx_req = i_tx_req & i_tx_en;
    wire w_rx_req = i_rx_req & i_rx_en;

    wire w_start_tx = w_tx_req & (r_state == S_IDLE);
    wire w_start_rx = w_rx_req & ~w_tx_req & (r_state == S_IDLE);

    // =========================================================
    // AHB response
    // =========================================================
    wire w_done  = i_hready;
    wire w_error = (i_hresp == HRESP_ERROR) & i_hready;

    // =========================================================
    // Static outputs
    // =========================================================
    assign o_hmastlock = 1'b0;
    assign o_hprot     = 4'b0011;
    assign o_hsize     = HSIZE_WORD;

    // =========================================================
    // FSM: State register
    // =========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state     <= S_IDLE;
            r_burst_cnt <= {BURST_CNT_WIDTH{1'b0}};
            r_burst_en  <= 1'b0;
            r_burst_last <= 1'b0;
        end
        else if (w_done) begin
            r_state     <= r_next;
            r_burst_cnt <= {BURST_CNT_WIDTH{1'b0}};
        end
    end

    // =========================================================
    // FSM: Next-state logic
    // =========================================================
    always @(*) begin
        r_next = r_state;

        case (r_state)
            S_IDLE: begin
                if (w_start_tx)
                    r_next = S_TX;
                else if (w_start_rx)
                    r_next = S_RX;
            end

            S_TX: begin
                if (w_error) begin
                    r_next = S_ERR;
                end else if (w_done) begin
                    if (w_len_eq0 || w_burst_last) begin
                        // End of TX transfer
                        if (w_rx_req) begin
                            r_next = S_RX;
                        end else begin
                            r_next = S_IDLE;
                        end
                    end else begin
                        // Continue TX
                        r_next = S_TX;
                    end
                end
            end

            S_RX: begin
                if (w_error) begin
                    r_next = S_ERR;
                end else if (w_done) begin
                    if (w_rx_len_eq0) begin
                        // End of RX transfer (all data written)
                        if (w_tx_req) begin
                            r_next = S_TX;
                        end else if (w_rx_req) begin
                            r_next = S_RX;
                        end else begin
                            r_next = S_IDLE;
                        end
                    end else begin
                        r_next = S_RX;
                    end
                end
            end

            S_ERR: begin
                // After ERROR cycle completes, return to IDLE
                if (w_done)
                    r_next = S_IDLE;
            end

            default: r_next = S_IDLE;
        endcase
    end

    // =========================================================
    // FSM: Burst control
    // =========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_burst_en   <= 1'b0;
            r_burst_last <= 1'b0;
        end else if (w_start_tx) begin
            r_burst_en   <= i_tx_burst_en & (i_tx_len > 16'd4);
            r_burst_last <= 1'b0;
        end else if (w_start_rx) begin
            r_burst_en   <= i_rx_burst_en;
            r_burst_last <= 1'b0;
        end else if (w_done && !w_error) begin
            if (r_state == S_TX || r_state == S_RX) begin
                // Set last flag one beat before actual last
                if (r_burst_cnt == (BURST_LENGTH[BURST_CNT_WIDTH-1:0] - 2'b10)) begin
                    r_burst_last <= 1'b1;
                    r_burst_en   <= 1'b0;
                end else begin
                    r_burst_last <= 1'b0;
                end
            end
        end
    end

    // =========================================================
    // AHB outputs: Address phase
    // =========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_htrans <= HTRANS_IDLE;
            o_hwrite <= 1'b0;
            o_haddr  <= 32'd0;
            o_hburst <= HBURST_SINGLE;
            o_hsel   <= 1'b0;
            o_hwdata <= 32'd0;
        end else if (w_done) begin
            case (r_next)
                S_IDLE: begin
                    o_htrans <= HTRANS_IDLE;
                    o_hwrite <= 1'b0;
                    o_hsel   <= 1'b0;
                end

                S_TX: begin
                    if (r_state == S_IDLE || r_state == S_RX || r_state == S_ERR) begin
                        // Start TX
                        o_htrans <= HTRANS_NONSEQ;
                        o_hwrite <= 1'b0;
                        o_haddr  <= {r_tx_addr, 2'b00};
                        o_hburst <= r_burst_en ? HBURST_TYPE : HBURST_SINGLE;
                        o_hsel   <= 1'b1;
                    end else begin
                        // Continue TX burst
                        o_htrans <= HTRANS_SEQ;
                        o_hwrite <= 1'b0;
                        o_haddr  <= o_haddr + 32'd4;
                        o_hsel   <= 1'b1;
                    end
                end

                S_RX: begin
                    if (r_state == S_IDLE || r_state == S_TX || r_state == S_ERR) begin
                        // Start RX
                        o_htrans <= HTRANS_NONSEQ;
                        o_hwrite <= 1'b1;
                        o_haddr  <= {r_rx_addr, 2'b00};
                        o_hburst <= r_burst_en ? HBURST_TYPE : HBURST_SINGLE;
                        o_hsel   <= 1'b1;
                        o_hwdata <= i_rx_wdata;
                    end else begin
                        // Continue RX burst
                        o_htrans <= HTRANS_SEQ;
                        o_hwrite <= 1'b1;
                        o_haddr  <= o_haddr + 32'd4;
                        o_hsel   <= 1'b1;
                        o_hwdata <= i_rx_wdata;
                    end
                end

                S_ERR: begin
                    o_htrans <= HTRANS_NONSEQ;
                    o_hsel   <= 1'b0;
                end

                default: begin
                    o_htrans <= HTRANS_IDLE;
                    o_hwrite <= 1'b0;
                    o_hsel   <= 1'b0;
                end
            endcase
        end
    end

    // =========================================================
    // Length and address tracking
    // =========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_tx_len     <= 16'd0;
            r_tx_addr    <= 30'd0;
            r_rx_addr    <= 30'd0;
            r_tx_lsb_rst <= 2'd0;
        end
        else if (w_done && !w_error) begin
            // Latch initial address and byte offset
            if (w_start_tx) begin
                r_tx_len     <= i_tx_len;
                r_tx_addr    <= i_tx_addr;
                r_tx_lsb_rst <= i_tx_addr_lsb;
            end
            // On each TX beat: advance pointer, decrement length
            else if (r_state == S_TX && !w_len_eq0) begin
                r_tx_addr    <= r_tx_addr + 1'b1;
                r_tx_lsb_rst <= 2'd0;  // after first beat, always word-aligned

                if (w_len_lt4) begin
                    r_tx_len <= 16'd0;
                end
                else begin
                    case (r_tx_lsb_rst)
                        2'd0: r_tx_len <= r_tx_len - 16'd4;
                        2'd1: r_tx_len <= r_tx_len - 16'd3;
                        2'd2: r_tx_len <= r_tx_len - 16'd2;
                        2'd3: r_tx_len <= r_tx_len - 16'd1;
                        default: r_tx_len <= r_tx_len - 16'd4;
                    endcase
                end
            end

            if (w_start_rx) begin
                r_rx_addr <= i_rx_addr;
                r_rx_len  <= i_rx_len;
            end
            else if (r_state == S_RX && !w_rx_len_eq0) begin
                r_rx_addr <= r_rx_addr + 1'b1;

                if (w_rx_len_lt4) begin
                    r_rx_len <= 16'd0;
                end
                else begin
                    r_rx_len <= r_rx_len - 16'd4;
                end
            end
        end
    end

    // =========================================================
    // TX outputs
    // =========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_tx_ack     <= 1'b0;
            o_tx_rdata   <= 32'd0;
            o_tx_ptr_inc <= 1'b0;
            o_tx_err     <= 1'b0;
        end else begin
            o_tx_ack     <= 1'b0;
            o_tx_ptr_inc <= 1'b0;
            o_tx_err     <= 1'b0;

            if (r_state == S_TX && w_done && !w_error) begin
                o_tx_ack     <= 1'b1;
                o_tx_rdata   <= i_hrdata;
                o_tx_ptr_inc <= 1'b1;
            end

            if (r_state == S_TX && w_error) begin
                o_tx_err <= 1'b1;
            end
        end
    end

    // =========================================================
    // RX outputs
    // =========================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_rx_ack <= 1'b0;
            o_rx_err <= 1'b0;
            o_rx_ptr_inc <= 1'b0;
        end else begin
            o_rx_ack <= 1'b0;
            o_rx_err <= 1'b0;
            o_rx_ptr_inc <= 1'b0;

            if (r_state == S_RX && w_done && !w_error) begin
                o_rx_ack <= 1'b1;
                o_rx_ptr_inc <= 1'b1;
            end

            if (r_state == S_RX && w_error) begin
                o_rx_err <= 1'b1;
            end
        end
    end

endmodule
