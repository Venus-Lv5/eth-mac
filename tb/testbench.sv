module testbench;
  import uvm_pkg::*;
  import test_pkg::*;
  import ahb_pkg::*;
  import phy_pkg::*;

  ahb_if ahb_vif();
  phy_if phy_vif();

  eth_top u_dut(
    .i_hclk       (ahb_vif.HCLK),
    .i_hresetn    (ahb_vif.HRESETn),
    .i_haddr      (ahb_vif.HADDR),
    .i_hburst     (ahb_vif.HBURST),
    .i_hmastlock  (ahb_vif.HMASTLOCK),
    .i_hprot      (ahb_vif.HPROT),
    .i_hsize      (ahb_vif.HSIZE),
    .i_hsel       (ahb_vif.HSEL),
    .i_htrans     (ahb_vif.HTRANS),
    .i_hwdata     (ahb_vif.HWDATA),
    .i_hwrite     (ahb_vif.HWRITE),
    .i_hready     (ahb_vif.HREADYOUT),
    .o_hrdata     (ahb_vif.HRDATA),
    .o_hreadyout  (ahb_vif.HREADYOUT),
    .o_hresp      (ahb_vif.HRESP),


    .i_mtx_clk    (phy_vif.TX_CLK),
    .o_mtxd       (phy_vif.TXD),
    .o_mtxen      (phy_vif.TX_EN),
    .o_mtxerr     (phy_vif.TX_ERR),

    .i_mrx_clk    (phy_vif.RX_CLK),
    .i_mrxd       (phy_vif.RXD),
    .i_mrxdv      (phy_vif.RX_DV),
    .i_mrxerr     (phy_vif.RX_ERR),
    .i_mcoll      (phy_vif.COL),
    .i_mcrs       (phy_vif.CRS),

    .o_irq        (ahb_vif.interrupt)
  );

	initial begin
		ahb_vif.HRESETn = 0;
		#100ns; ahb_vif.HRESETn = 1;
	end

	initial begin
		ahb_vif.HCLK = 0;
		forever begin
			#5ns;
			ahb_vif.HCLK = ~ahb_vif.HCLK;
		end
	end

  initial begin
    uvm_config_db #(virtual ahb_if)::set(uvm_root::get(), "uvm_test_top", "ahb_vif", ahb_vif);
    uvm_config_db #(virtual phy_if)::set(uvm_root::get(), "uvm_test_top", "phy_vif", phy_vif);

    run_test();
  end

endmodule
