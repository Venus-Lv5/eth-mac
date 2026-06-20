`ifndef GUARD_ETH_TEST_PKG__SV
`define GUARD_ETH_TEST_PKG__SV

package test_pkg;
  import uvm_pkg::*;
  import ahb_pkg::*;
  import phy_pkg::*;
  import env_pkg::*;
  import seq_pkg::*;
  import eth_regmodel_pkg::*;

  `include "eth_base_test.sv"
  `include "full_100M_normal_uni_test.sv"
  `include "full_10M_normal_uni_test.sv"
  `include "full_100M_normal_bro_test.sv"
  `include "full_10M_normal_bro_test.sv"
  `include "full_100M_normal_multi_test.sv"
  `include "full_10M_normal_multi_test.sv"
  `include "full_100M_normal_pro_test.sv"
  `include "full_10M_normal_pro_test.sv"
  `include "full_100M_rx_pause_test.sv"
  `include "full_10M_rx_pause_test.sv"
  `include "full_100M_tx_pause_test.sv"
  `include "full_10M_tx_pause_test.sv"
  `include "int_tx_done_100M_test.sv"
  `include "int_tx_done_10M_test.sv"
  `include "int_tx_err_100M_test.sv"
  `include "int_tx_err_10M_test.sv"
  `include "int_rx_avail_100M_test.sv"
  `include "int_rx_avail_10M_test.sv"
  `include "int_rx_busy_100M_test.sv"
  `include "int_rx_busy_10M_test.sv"
  `include "int_rx_err_100M_test.sv"
  `include "int_rx_err_10M_test.sv"
  `include "int_rx_pause_seen_100M_test.sv"
  `include "int_rx_pause_seen_10M_test.sv"
  `include "reg_default_test.sv"
  `include "reg_rw_test.sv"

endpackage: test_pkg

`endif
