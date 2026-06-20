class int_rx_busy_10M_test extends eth_base_test;
  `uvm_component_utils(int_rx_busy_10M_test)

  function new(string name="int_rx_busy_10M_test", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    assert(cfg.randomize() with {
      mode == phy_config::FULL; freq == phy_config::MII_10M;
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
    phy_eth_frame_seq rx_seq;

    phase.raise_objection(this);

    wdata_q.push_back(config_mac_addr_l());
    wdata_q.push_back(config_mac_addr_h());
    wdata_q.push_back(32'h0000_0000);
    wdata_q.push_back(32'h0000_0008);                 // IER: RX_BUSY
    wdata_q.push_back(config_mac_ctrl());
    burst_write_reg_range(10'h00, 10'h10, wdata_q, 1);

    wdata_q.delete();
    wdata_q.push_back(32'h0000_0000);
    wdata_q.push_back(32'h0000_0000);
    burst_write_reg_range(10'h20, 10'h24, wdata_q, 1);

    repeat (25) @(posedge phy_vif.RX_CLK);
    for (int frame_idx = 0; frame_idx < 3; frame_idx++) begin
      rx_seq = phy_eth_frame_seq::type_id::create($sformatf("rx_busy_seq_%0d", frame_idx));
      assert(rx_seq.randomize() with {
        len == cfg.tx_len;
        dst_mac == cfg.mac_addr;
        src_mac == cfg.phy_addr;
      })
      else `uvm_fatal(get_type_name(), "Failed to randomize RX_BUSY sequence")
      rx_seq.start(env.phy_agt.sequencer);
      repeat (25) @(posedge phy_vif.RX_CLK);
    end

    wait_interrupt_or_timeout(got_irq);
    regmodel.FSR.read(status, rdata);
    if (!got_irq)
      `uvm_error(get_type_name(), "RX_BUSY interrupt timeout")
    if (!rdata[5])
      `uvm_error(get_type_name(), $sformatf("RX_BUSY status mismatch: FSR=0x%08h", rdata))
    if (got_irq && rdata[5])
      `uvm_info(get_type_name(), $sformatf("INT: RX_BUSY IRQ_SEEN=%0b FSR=0x%08h", got_irq, rdata), UVM_NONE)

    phase.drop_objection(this);
  endtask
endclass
