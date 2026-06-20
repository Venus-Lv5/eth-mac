class full_10M_normal_bro_test extends eth_base_test;
  `uvm_component_utils(full_10M_normal_bro_test)

  function new(string name="full_10M_normal_bro_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		assert(cfg.randomize() with {
			mode      == phy_config::FULL;
      freq      == phy_config::MII_10M;
      mac_addr 	== 48'h11_22_33_44_55_66;
      phy_addr 	== 48'hAA_BB_CC_DD_EE_FF;
      hash			== 0;
      pro				== 0;
      fil_en		== 0;
      bro				== 1;
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

    fork
      begin
        wdata_q.delete();
        random_payload(cfg.tx_len, wdata_q);

        for (int i =0; i < (cfg.tx_len+3)/4; i++) begin
          regmodel.TX_DATA.write(status, wdata_q[i]);
        end
        regmodel.TX_CMD.write(status, 32'h0000_0001);
      end

      begin
        phy_eth_frame_seq rx_seq;
        repeat (25) @(posedge phy_vif.RX_CLK);
        rx_seq = phy_eth_frame_seq::type_id::create("rx_seq");
        assert(rx_seq.randomize() with {
          dst_mac == 48'hFF_FF_FF_FF_FF_FF;
          src_mac == cfg.phy_addr;
        })
        else `uvm_fatal(get_type_name(), "Failed to randomize PHY RX frame sequence")
        rx_seq.start(env.phy_agt.sequencer);

        wait_interrupt_or_timeout(got_irq);
        if (got_irq) begin
          regmodel.RX_LEN.read(status, rdata);
          rx_len = rdata;

          for (int i =0; i < (rx_len+3)/4; i++) begin
            regmodel.RX_DATA.read(status, rdata);
          end
        end
      end
    join
    phase.drop_objection(this);



  endtask
endclass
