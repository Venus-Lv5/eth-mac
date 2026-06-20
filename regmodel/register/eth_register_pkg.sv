`include "uvm_macros.svh"

package eth_register_pkg;

  import uvm_pkg::*;

  `include "eth_MAC_SA_LOW_reg.sv"
  `include "eth_MAC_SA_HIGH_reg.sv"
  `include "eth_PAUSE_CTRL_reg.sv"
  `include "eth_IER_reg.sv"
  `include "eth_MAC_CTRL_reg.sv"
  `include "eth_HASH_0_reg.sv"
  `include "eth_HASH_1_reg.sv"
  `include "eth_TX_DA_LOW_reg.sv"
  `include "eth_TX_DA_HIGH_reg.sv"
  `include "eth_TX_LEN_reg.sv"
  `include "eth_TX_DATA_reg.sv"
  `include "eth_TX_CMD_reg.sv"
  `include "eth_FSR_reg.sv"
  `include "eth_RX_LEN_reg.sv"
  `include "eth_RX_DATA_reg.sv"
  `include "eth_RX_CMD_reg.sv"
endpackage

