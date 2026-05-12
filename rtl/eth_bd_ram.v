`timescale 1ns/1ps

module eth_bd_ram #(
   parameter integer TX_BD_NUM = 64,
   parameter integer RX_BD_NUM = 64
) (
   input wire        i_clk,
   input wire        i_rst_n,

   // AHB Slave request
   input wire        i_ahb_req,
   input wire        i_ahb_wr,
   input wire [3:0]  i_ahb_be,
   input wire [9:0]  i_ahb_addr,
   input wire [31:0] i_ahb_wdata,
   output wire [31:0] o_ahb_rdata,
   output reg         o_ahb_ack,

   // TX DMA request
   input wire        i_txe_en,
   input wire        i_tx_db_rd,
   input wire        i_tx_ptr_rd,
   input wire        i_tx_stt_wr,
   input wire        i_tx_wrap,
   input wire [31:0] i_tx_wdata,
   output wire [31:0] o_tx_rdata,

   // RX DMA request
   input wire        i_rxe_en,
   input wire        i_rx_db_rd,
   input wire        i_rx_ptr_rd,
   input wire        i_rx_stt_wr,
   input wire        i_rx_wrap,
   input wire [31:0] i_rx_wdata,
   output wire [31:0] o_rx_rdata
);

   // Request
   reg r_ahb_state;
   reg r_tx_state;
   reg r_rx_state;

   reg r_ahb_state_q;
   reg r_tx_state_q;
   reg r_rx_state_q;

   // Needed
   reg r_tx_needed;
   reg r_rx_needed;

   // SRAM
   reg [7:0]   r_addr;
   reg [31:0]  r_din;
   reg [3:0]   r_wr;
   reg         r_rd;
   wire [31:0] w_dout;

   // BD indices (managed internally)
   reg [5:0]  r_tx_index;
   reg [5:0]  r_rx_index;

   // State
   reg [1:0] r_state;
   reg [1:0] r_state_q;

   localparam SRC_AHB   = 2'd0;
   localparam SRC_TX    = 2'd1;
   localparam SRC_RX    = 2'd2;

   // AHB address range: 0x400-0x7FF
   // Internally mapped to 0x00-0xFF
   wire [7:0] w_ahb_ram_addr = i_ahb_addr[9:2]; 

   // Decriptor word address mapping
   // TX: indices 0..63, addresses 0x00-0x7F
   // RX: indices 0..63, addresses 0x80-0xFF
   // Each DB = 2 words (word0 = control, word1 = pointer)
   wire [7:0] w_tx_word0_addr = {1'b0, r_tx_index, 1'b0};
   wire [7:0] w_tx_word1_addr = {1'b0, r_tx_index, 1'b1};
   wire [7:0] w_rx_word0_addr = {1'b1, r_rx_index, 1'b0};
   wire [7:0] w_rx_word1_addr = {1'b1, r_rx_index, 1'b1};

   // SRAM instance
   eth_sram_256x32 u_db_ram(
      .i_clk(i_clk),
      .i_ce(1'b1),
      .i_wr(r_wr),
      .i_rd(r_rd),
      .i_addr(r_addr),
      .i_din(r_din),
      .o_dout(w_dout)
   );

   // Capture TX request
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n)
         r_tx_needed <= 0;
      else if (i_txe_en && (i_tx_db_rd || i_tx_ptr_rd || i_tx_stt_wr))
         r_tx_needed <= 1;
      else if (r_tx_state_q)
         r_tx_needed <= 0;
   end

   // Capture RX request
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n)
         r_rx_needed <= 0;
      else if (i_rxe_en && (i_rx_db_rd || i_rx_ptr_rd || i_rx_stt_wr))
         r_rx_needed <= 1;
      else if (r_rx_state_q)
         r_rx_needed <= 0;
   end

   // Arbitration
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
         r_ahb_state    <= 1'b1;
         r_tx_state     <= 1'b0;
         r_rx_state     <= 1'b0;

         r_addr         <= 8'h0;
         r_din          <= 32'h0;
         r_wr           <= 4'h0;
         r_rd           <= 1'b0;

         r_state        <= SRC_AHB;
      end
      else begin
         r_wr           <= 4'h0;
         r_rd           <= 1'b0;

         if (r_tx_needed) begin
            r_ahb_state <= 1'b0;
            r_tx_state  <= 1'b1;
            r_rx_state  <= 1'b0;
            r_state     <= SRC_TX;

            if (i_tx_stt_wr) begin  
               r_addr   <= w_tx_word0_addr;
               r_din    <= i_tx_wdata;
               r_wr     <= 4'hF;
            end
            else if (i_tx_ptr_rd) begin
               r_addr   <= w_tx_word1_addr;
               r_rd     <= 1'b1;
            end
            else if (i_tx_db_rd) begin
               r_addr   <= w_tx_word0_addr;
               r_rd     <= 1'b1;
            end
         end
         else if (r_rx_needed) begin
            r_ahb_state <= 1'b0;
            r_tx_state  <= 1'b0;
            r_rx_state  <= 1'b1;
            r_state     <= SRC_RX;

            if (i_rx_stt_wr) begin
               r_addr   <= w_rx_word0_addr;
               r_din    <= i_rx_wdata;
               r_wr     <= 4'hF;
            end
            else if (i_rx_ptr_rd) begin
               r_addr   <= w_rx_word1_addr;
               r_rd     <= 1'b1;
            end   
            else if (i_rx_db_rd) begin
               r_addr   <= w_rx_word0_addr;
               r_rd     <= 1'b1;
            end
         end
         else begin
            r_ahb_state    <= 1'b1;
            r_tx_state     <= 1'b0;
            r_rx_state     <= 1'b0;
            r_state        <= SRC_AHB;

            r_addr         <= w_ahb_ram_addr;
            r_din          <= i_ahb_wdata;
            r_wr           <= (i_ahb_req && i_ahb_wr) ? i_ahb_be : 4'h0;
            r_rd           <= (i_ahb_req && !i_ahb_wr);
         end
      end
   end

   // 1-cycle delayed stage/source tracking
   // RAM read data becomes valid in next cycle
   always @(posedge i_clk or negedge i_rst_n) begin
      if (~i_rst_n) begin
         r_ahb_state_q     <= 1'b0;
         r_tx_state_q      <= 1'b0;
         r_rx_state_q      <= 1'b0;
         r_state_q         <= SRC_AHB;
      end
      else begin
         r_ahb_state_q     <= r_ahb_state;
         r_tx_state_q      <= r_tx_state;
         r_rx_state_q      <= r_rx_state;
         r_state_q         <= r_state;
      end
   end

   // Return read data to the correct requester
   // RAM has 1-cycle latency: address driven in cycle N, data valid in cycle N+1
   // r_state_q tracks which source was granted access in the previous cycle
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
         o_ahb_rdata <= 32'h0;
      end else begin
         if (r_state_q == SRC_AHB && !i_ahb_wr)
            o_ahb_rdata <= w_dout;
      end
   end

   // TX DMA sees valid BD data in cycle AFTER o_tx_db_rd / o_tx_ptr_rd is asserted
   // because of 1-cycle RAM read latency
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
         o_tx_rdata <= 32'h0;
      end else begin
         if (r_state_q == SRC_TX && !i_tx_stt_wr)
            o_tx_rdata <= w_dout;
      end
   end

   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
         o_rx_rdata <= 32'h0;
      end else begin
         if (r_state_q == SRC_RX && !i_rx_stt_wr)
            o_rx_rdata <= w_dout;
      end
   end

   // Assert ack when host AHB transaction was served in previous cycle
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n)
         o_ahb_ack   <= 1'b0;
      else
         o_ahb_ack   <= r_ahb_state_q && i_ahb_req;
   end

   // TX current BD index update
   // Advances when TX DMA writes status back to BD
   localparam [5:0] TX_BD_MAX = TX_BD_NUM - 1;
   localparam [5:0] RX_BD_MAX = RX_BD_NUM - 1;

   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n)
         r_tx_index <= 6'd0;
      else if (i_tx_stt_wr) begin
         // Wrap at TX_BD_NUM boundary
         if (i_tx_wrap || (r_tx_index == TX_BD_MAX))
            r_tx_index <= 6'd0;
         else
            r_tx_index <= r_tx_index + 6'd1;
      end
   end

   // RX current BD index update
   // Wraps at RX_BD_NUM boundary
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n)
         r_rx_index <= 6'd0;
      else if (i_rx_stt_wr) begin
         if (i_rx_wrap || (r_rx_index == RX_BD_MAX))
            r_rx_index <= 6'd0;
         else
            r_rx_index <= r_rx_index + 6'd1;
      end
   end

endmodule