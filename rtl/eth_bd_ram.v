`timescale 1ns/1ps

module eth_db_ram (
   input wire        i_clk,
   input wire        i_rst_n,

    //  AHB request
   input wire        i_ahb_req,                    //host request
   input wire        i_ahb_wr,                     //write or read
   input wire [3:0]  i_ahb_be,                     //byte enable
   input wire [7:0]  i_ahb_addr,                   //address
   input wire [31:0] i_ahb_wdata,                  //write data
   output reg [31:0] o_ahb_rdata;                 //read data
   output reg        o_ahb_ack,                    // 

   // TX request
   input wire        i_txe_en,                     //enable tx dma engine
   input wire        i_tx_db_rd,                   //tx db read (word0)
   input wire        i_tx_ptr_rd,                  //tx ptr read (word 1)
   input wire        i_tx_stt_wr,                  //tx status write
   input wire        i_tx_wrap,                    //wrap to next TX BD
   input wire [31:0] i_tx_wdata,                   //TX write data
   output reg [31:0] o_tx_rdata,                  //TX read data
   output reg [5:0]  o_tx_index,                   //Current TX decriptor 

   //RX request
   input wire        i_rxe_en,                     //enable rx dma engine
   input wire        i_rx_db_rd,                   //rx db read (word0)
   input wire        i_rx_ptr_rd,                  //rx ptr read (word1)
   input wire        i_rx_stt_wr,                  //rx status write
   input wire        i_rx_wrap,                    //wrap to next RX DB
   input wire [31:0] i_rx_wdata,                   //RX write data
   output reg [31:0] o_rx_rdata,                  //RX read data
   output reg [5:0]  o_rx_index                    //Current RX decriptor
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

   // State
   reg r_state, r_state_q;

   localparam SRC_AHB   = 2'd0;
   localparam SRC_TX    = 2'd1;
   localparam SRC_RX    = 2'd2; 

   // Decriptor word address mapping
   // TX: 0x00 - 0x7F
   // RX: 0x80 - 0xFF
   // Each DB 2 word
   wire [7:0] w_tx_word0_addr;
   wire [7:0] w_tx_word1_addr;
   wire [7:0] w_rx_word0_addr;
   wire [7:0] w_rx_word1_addr;

   assign w_tx_word0_addr = {1'b0, o_tx_index, 1'b0};
   assign w_tx_word1_addr = {1'b0, o_tx_index, 1'b1};
   assign w_rx_word0_addr = {1'b1, o_rx_index, 1'b0};
   assign w_rx_word1_addr = {1'b1, o_rx_index, 1'b1};

   // SRAM instance
   eth_sram_256x32 u_db_ram(
      .i_clk(i_clk),
      .i_ce(1'b1),
      .i_wr(r_wr),
      .i_rd(r_rd),
      .i_addr(r_addr),
      .i_din(r_din),
      .o_dout(w_dout)
   )

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
               r_din    <= i_rx_db_rd;
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

            r_addr         <= i_ahb_addr;
            r_din          <= i_ahb_wdata;
            r_wr           <= (i_ahb_req && i_ahb_wr)? i_ahb_be : 4'h0;
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
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
         o_ahb_rdata       <= 32'h0;
         o_tx_rdata        <= 32'h0;
         o_rx_rdata        <= 32'h0;         
      end
      else begin
         if (r_ahb_state_q && !i_ahb_wr && i_ahb_req)
            o_ahb_rdata    <= w_dout;
         if (r_state_q == SRC_TX && r_tx_state_q && !i_tx_stt_wr)
            o_tx_rdata     <= w_dout;
         if (r_state_q == SRC_RX && r_rx_state_q && !i_rx_stt_wr)
            o_rx_rdata     <= w_dout;
      end
   end

   //Assert ack when host stage was served in previous cycle
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n)
         o_ahb_ack   <= 1'b0;
      else 
         o_ahb_ack   <= r_ahb_state_q && i_ahb_req;
   end

   // TX current BD index update
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) 
         o_tx_index     <= 6'h0;
      else if (i_tx_stt_wr) begin
         if (i_tx_wrap)
            o_tx_index  <= 6'h0;
         else
            o_tx_index  <= o_tx_index + 6'h1;
      end
   end

   // RX current BD index update
   always @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) 
         o_rx_index     <= 6'h0;
      else if (i_rx_stt_wr) begin
         if (i_rx_wrap)
            o_rx_index  <= 6'h0;
         else
            o_rx_index  <= o_rx_index + 6'h1;
      end
   end
endmodule