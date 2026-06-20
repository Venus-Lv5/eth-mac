`ifndef GUARD_PHY_PACKAGE__SV
`define GUARD_PHY_PACKAGE__SV

package phy_pkg;
  import uvm_pkg::*;

  `include "phy_config.sv"
  `include "phy_transaction.sv"
  `include "phy_sequencer.sv"
  `include "phy_driver.sv"
  `include "phy_monitor.sv"
  `include "phy_agent.sv"
  `include "phy_error_catcher.sv"

endpackage: phy_pkg

`endif
