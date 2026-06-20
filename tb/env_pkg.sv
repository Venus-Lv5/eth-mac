`ifndef GUARD_ETH_ENV_PKG__SV
`define GUARD_ETH_ENV_PKG__SV

package env_pkg;
  import uvm_pkg::*;
  import ahb_pkg::*;
  import phy_pkg::*;
  import eth_regmodel_pkg::*;

  `include "eth_scoreboard.sv"
  `include "eth_environment.sv"

endpackage

`endif
