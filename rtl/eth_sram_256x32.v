`timescale 1ns/1ps

module eth_sram_256x32 (
   input wire       i_clk,
   input wire       i_ce,
   input wire [3:0] i_wr,
   input wire       i_rd,
   input wire [7:0] i_addr,
   input wire [31:0] i_din,
   output reg [31:0] o_dout
);

   reg [31:0] mem [255:0];
   
   always @(posedge i_clk) begin
      if (ce) begin
            if (wr[0])
               mem[i_addr][7:0]        <= i_din[7:0];
            if (wr[1])
               mem([i_addr][15:8])     <= i_din[15:8];
            if (wr[2])
               mem[i_addr][23:16]      <= i_din[23:16];
            if (wr[3])
               mem([i_addr][31:24])    <= i_din[31:24];

               if (i_rd)
                  o_dout <= mem[i_addr];
      end
   end
endmodule