`ifndef GUARD_PHY_SEQ_PKG__SV
`define GUARD_PHY_SEQ_PKG__SV

package seq_pkg;
  import uvm_pkg::*;
  import phy_pkg::*;
  import ahb_pkg::*;

  `include "eth_ahb_burst_write_seq.sv"
  `include "phy_eth_frame_seq.sv"
  `include "phy_bad_fcs_frame_seq.sv"
  `include "phy_pause_frame_seq.sv"
  `include "phy_col_delay_seq.sv"

endpackage: seq_pkg

`endif
