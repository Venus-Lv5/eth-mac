class int_tx_err_100M_test extends eth_base_test;
  `uvm_component_utils(int_tx_err_100M_test)

  function new(string name="int_tx_err_100M_test", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    assert(cfg.randomize() with {
      mode == phy_config::FULL; freq == phy_config::MII_100M;
      mac_addr == 48'h12_22_33_44_55_66;
      phy_addr == 48'hAA_BB_CC_DD_EE_FF;
      tx_len == 46; hash == 0; pro == 0; fil_en == 0; bro == 0;
    })
    else `uvm_fatal(get_type_name(), "Failed to randomize phy_config")
    config_mac(cfg);
  endfunction

  virtual task run_phase(uvm_phase phase);
    uvm_status_e status;
    bit [31:0] wdata_q[$];
    bit [31:0] rdata;
    bit got_irq;

    phase.raise_objection(this);

    wdata_q.push_back(config_mac_addr_l());
    wdata_q.push_back(config_mac_addr_h());
    wdata_q.push_back(32'h0000_0000);
    wdata_q.push_back(32'h0000_0002);                 // IER: TX_ERR
    wdata_q.push_back(config_mac_ctrl());
    burst_write_reg_range(10'h00, 10'h10, wdata_q, 1);

    // Write TX_DATA without an active TX_LEN fill.
    regmodel.TX_DATA.write(status, 32'hDEAD_BEEF);

    wait_interrupt_or_timeout(got_irq);
    regmodel.FSR.read(status, rdata);
    if (!got_irq)
      `uvm_error(get_type_name(), "TX_ERR interrupt timeout")
    if (!rdata[3])
      `uvm_error(get_type_name(), $sformatf("TX_ERR status mismatch: FSR=0x%08h", rdata))
    if (got_irq && rdata[3])
      `uvm_info(get_type_name(), $sformatf("INT: TX_ERR IRQ_SEEN=%0b FSR=0x%08h", got_irq, rdata), UVM_NONE)

    phase.drop_objection(this);
  endtask
endclass
