class full_10M_tx_pause_test extends eth_base_test;
  `uvm_component_utils(full_10M_tx_pause_test)

  function new(string name="full_10M_tx_pause_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		assert(cfg.randomize() with {
			mode      == phy_config::FULL;
      freq      == phy_config::MII_10M;
      mac_addr 	== 48'h11_22_33_44_55_66;
      phy_addr 	== 48'hAA_BB_CC_DD_EE_FF;
      tx_len    == 46;
      hash			== 0;
      pro				== 0;
      fil_en		== 0;
      bro				== 0;
		})
		else `uvm_fatal(get_type_name(), $sformatf("Failed to random uart_config"))

    config_mac(cfg);
  endfunction

  virtual task run_phase(uvm_phase phase);
    uvm_status_e status;

    bit [31:0] wdata_q[$];
    bit [31:0] rdata;
    bit [31:0] rx_len;
    bit got_irq;
    bit tx_pause_seen;
    bit tx_release_seen;

    phase.raise_objection(this);
    wdata_q.delete();

    wdata_q.push_back(config_mac_addr_l());
    wdata_q.push_back(config_mac_addr_h());
    wdata_q.push_back(32'h0000_0003);                 //PAUSE control
    wdata_q.push_back(32'h0000_0004);                 //IER
    wdata_q.push_back(config_mac_ctrl());
    burst_write_reg_range(10'h00, 10'h10, wdata_q, 1);

    wdata_q.delete();
    wdata_q.push_back(31'h0);
    wdata_q.push_back(31'h0);
    burst_write_reg_range(10'h20, 10'h24, wdata_q, 1);

    wdata_q.delete();
    wdata_q.push_back(config_phy_addr_l());
    wdata_q.push_back(config_phy_addr_h());
    wdata_q.push_back(config_tx_len());
    burst_write_reg_range(10'h40, 10'h48, wdata_q, 1);

    repeat (25) @(posedge phy_vif.RX_CLK);

    for (int frame_idx = 0; frame_idx < 2; frame_idx++) begin
      phy_eth_frame_seq rx_seq;
      rx_seq = phy_eth_frame_seq::type_id::create($sformatf("rx_seq_%0d", frame_idx));
      assert(rx_seq.randomize() with {
        len     == cfg.tx_len;
        dst_mac == cfg.mac_addr;
        src_mac == cfg.phy_addr;
      })
      else `uvm_fatal(get_type_name(), "Failed to randomize PHY RX frame sequence")
      rx_seq.start(env.phy_agt.sequencer);
      repeat (25) @(posedge phy_vif.RX_CLK);
    end

    tx_pause_seen = 0;
    repeat (2000) begin
      @(posedge phy_vif.TX_CLK);
      if (phy_vif.TX_EN === 1'b1) begin
        tx_pause_seen = 1;
        break;
      end
    end

    if (!tx_pause_seen)
      `uvm_error(get_type_name(), "DUT did not transmit PAUSE frame when RX buffers were full")
    else begin
      wait (phy_vif.TX_EN === 1'b0);
      repeat (20) @(posedge phy_vif.TX_CLK);
    end

    wait_interrupt_or_timeout(got_irq);
    if (got_irq) begin
      regmodel.RX_LEN.read(status, rdata);
      rx_len = rdata;

      for (int i =0; i < (rx_len+3)/4; i++) begin
        regmodel.RX_DATA.read(status, rdata);
      end
      regmodel.RX_CMD.write(status, 32'h0000_0001);
    end
    else begin
      `uvm_error(get_type_name(), "RX interrupt was not asserted for first buffered frame")
    end

    tx_release_seen = 0;
    repeat (2000) begin
      @(posedge phy_vif.TX_CLK);
      if (phy_vif.TX_EN === 1'b1) begin
        tx_release_seen = 1;
        break;
      end
    end

    if (!tx_release_seen)
      `uvm_error(get_type_name(), "DUT did not transmit PAUSE release frame after RX buffer release")
    else begin
      wait (phy_vif.TX_EN === 1'b0);
      repeat (20) @(posedge phy_vif.TX_CLK);
    end

    wait_interrupt_or_timeout(got_irq);
    if (got_irq) begin
      regmodel.RX_LEN.read(status, rdata);
      rx_len = rdata;

      for (int i =0; i < (rx_len+3)/4; i++) begin
        regmodel.RX_DATA.read(status, rdata);
      end
      regmodel.RX_CMD.write(status, 32'h0000_0001);
    end
    else begin
      `uvm_error(get_type_name(), "RX interrupt was not asserted for second buffered frame")
    end

    phase.drop_objection(this);
  endtask
endclass
