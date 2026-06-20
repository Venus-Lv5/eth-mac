`include "uvm_macros.svh"

package eth_regmodel_pkg;

  import uvm_pkg::*;
  import ahb_pkg::*;
  import eth_register_pkg::*;

  `include "eth_reg2ahb_adapter.sv"
  `include "eth_reg_block.sv"
endpackage

