class eth_base_test extends uvm_test;
  `uvm_component_utils(eth_base_test)

	uvm_report_server svr;
	eth_environment env;

	eth_reg_block regmodel;

	virtual ahb_if ahb_vif;
	virtual phy_if phy_vif;

	phy_config cfg;
	phy_error_catcher err_catcher;

	time usr_timeout = 1s;

	function new(string name="eth_base_test", uvm_component parent);
		super.new(name, parent);
	endfunction

  virtual function void config_mac (phy_config c);
    cfg.phy_addr          = c.phy_addr;
    cfg.mac_addr          = c.mac_addr;
    cfg.mode              = c.mode;
    cfg.freq              = c.freq;
    cfg.hash              = c.hash;
    cfg.tx_len            = c.tx_len;
    cfg.bro               = c.bro;
    cfg.fil_en            = c.fil_en;
    cfg.pro               = c.pro;

    cfg.coll_det_delay    = c.coll_det_delay;
    cfg.pause_frame_delay = c.pause_frame_delay;
  endfunction

  virtual function bit[31:0] config_mac_addr_l();
    bit[31:0] mac_addr_l;

    mac_addr_l  = cfg.mac_addr[31:0];
    return mac_addr_l;
    `uvm_info(get_type_name(), $sformatf("Completed config MAC_SA_LOW: 0x%0h", mac_addr_l), UVM_LOW)
  endfunction

  virtual function bit[31:0] config_mac_addr_h();
    bit[31:0] mac_addr_h;

    mac_addr_h[15:0]  = cfg.mac_addr[47:32];
    mac_addr_h[31:16] = 0;
    return mac_addr_h;
    `uvm_info(get_type_name(), $sformatf("Completed config MAC_SA_HIGH: 0x%0h", mac_addr_h), UVM_LOW)
  endfunction

  virtual function bit[31:0] config_mac_ctrl();
    bit [31:0] mac_ctrl;

    mac_ctrl[5]     = (cfg.mode == phy_config::FULL) ? 1: 0;
    mac_ctrl[4]     = cfg.pro;
    mac_ctrl[3]     = cfg.fil_en;
    mac_ctrl[2]     = cfg.bro;
    mac_ctrl[1]     = 1'b1;
    mac_ctrl[0]     = 1'b1;
    mac_ctrl[31:6]  = 0;

    return mac_ctrl;
    `uvm_info(get_type_name(), $sformatf("Completed config MAC_CTRL: %0b", mac_ctrl), UVM_LOW)
  endfunction

  virtual function bit[31:0] config_phy_addr_l();
    bit[31:0] phy_addr_l;

    phy_addr_l  = cfg.phy_addr[31:0];
    return phy_addr_l;
    `uvm_info(get_type_name(), $sformatf("Completed config PHY_DA_LOW: 0x%0h", phy_addr_l), UVM_LOW)
  endfunction

  virtual function bit[31:0] config_phy_addr_h();
    bit[31:0] phy_addr_h;

    phy_addr_h[15:0]  = cfg.phy_addr[47:32];
    phy_addr_h[31:16] = 0;
    return phy_addr_h;
    `uvm_info(get_type_name(), $sformatf("Completed config PHY_DA_HIGH: 0x%0h", phy_addr_h), UVM_LOW)
  endfunction

  virtual function bit[31:0] config_tx_len();
    bit[31:0] tx_len;

    tx_len[15:0]    = cfg.tx_len;
    tx_len[31:16]   = 0;
    return tx_len;
    `uvm_info(get_type_name(), $sformatf("Completed config TX_LEN: %0d", tx_len), UVM_LOW)
  endfunction

  // Example:
  // bit [`AHB_DATA_WIDTH-1:0] wr_data_q[$];
  // for (int i = 0; i < 16; i++) wr_data_q.push_back($urandom());
  // burst_write_reg_range('h0000_0000, 'h0000_003C, wr_data_q);
  virtual task burst_write_reg_range(
    input bit[`AHB_ADDR_WIDTH-1:0] start_addr,
    input bit[`AHB_ADDR_WIDTH-1:0] end_addr,
    input bit[`AHB_DATA_WIDTH-1:0] data_q[$],
    input bit auto_fixed_burst = 1'b1
  );
    eth_ahb_burst_write_seq burst_seq;
    int unsigned access_bytes;
    int unsigned total_beats;

    access_bytes = (1 << ahb_transaction::SIZE_32BIT);

    if (end_addr < start_addr) begin
      `uvm_error(get_type_name(),
        $sformatf("burst_write_reg_range: invalid range start=0x%0h end=0x%0h",
                  start_addr, end_addr))
      return;
    end
    if ((start_addr % access_bytes) != 0 || (end_addr % access_bytes) != 0) begin
      `uvm_error(get_type_name(),
        $sformatf("burst_write_reg_range: unaligned address start=0x%0h end=0x%0h",
                  start_addr, end_addr))
      return;
    end

    total_beats = ((end_addr - start_addr) / access_bytes) + 1;
    if (data_q.size() < total_beats) begin
      `uvm_error(get_type_name(),
        $sformatf("burst_write_reg_range: need %0d data beats, got %0d",
                  total_beats, data_q.size()))
      return;
    end
    if (data_q.size() > total_beats) begin
      `uvm_info(get_type_name(),
        $sformatf("burst_write_reg_range: ignoring %0d extra data beats",
                  data_q.size() - total_beats),
        UVM_LOW)
    end

    `uvm_info(get_type_name(),
      $sformatf("burst_write_reg_range: start=0x%0h end=0x%0h beats=%0d auto_fixed_burst=%0b",
                start_addr, end_addr, total_beats, auto_fixed_burst),
      UVM_LOW)

    burst_seq = eth_ahb_burst_write_seq::type_id::create("burst_seq");
    burst_seq.start_addr = start_addr;
    burst_seq.end_addr = end_addr;
    burst_seq.auto_fixed_burst = auto_fixed_burst;
    burst_seq.data_q = data_q;
    burst_seq.start(env.ahb_agt.sequencer);

	  `uvm_info(get_type_name(), "burst_write_reg_range: completed", UVM_LOW)
  endtask

  
  task automatic random_payload(
    input  int unsigned byte_len,
    ref    bit [31:0] payload[$]
  );
	    int unsigned num_words;
	    int unsigned last_bytes;
	    bit [31:0] mask;
	    string payload_str;

    payload.delete();

    num_words = (byte_len + 3) / 4; // ceil(byte_len / 4)

    for (int i = 0; i < num_words; i++) begin
      payload.push_back($urandom());
    end

    // Nếu byte_len không chia hết cho 4, clear byte dư ở word cuối
    last_bytes = byte_len % 4;

	    if (last_bytes != 0 && num_words != 0) begin
	      mask = (32'h1 << (last_bytes * 8)) - 1;
	      payload[payload.size() - 1] &= mask;
	    end

	    payload_str = $sformatf("random_payload: byte_len=%0d num_words=%0d", byte_len, num_words);
	    foreach (payload[i]) begin
	      payload_str = {payload_str, $sformatf("\n  payload[%0d] = 32'h%08h", i, payload[i])};
	    end
	    `uvm_info(get_type_name(), payload_str, UVM_LOW)
	  endtask

  virtual task wait_interrupt_or_timeout(
    output bit got_irq,
    input int unsigned timeout_cycles = 0
  );
    int unsigned wait_cycles;

    got_irq = 0;
    wait_cycles = timeout_cycles;
    if (wait_cycles == 0)
      wait_cycles = (cfg.freq == phy_config::MII_10M) ? 300000 : 50000;

    fork
      begin
        wait (ahb_vif.interrupt == 1'b1);
        got_irq = 1;
      end

      begin
        repeat (wait_cycles) @(posedge ahb_vif.HCLK);
      end
    join_any
    disable fork;

    if (got_irq)
      `uvm_info(get_type_name(), "Interrupt detected", UVM_LOW)
    else
      `uvm_info(get_type_name(),
        $sformatf("Interrupt wait timeout after %0d HCLK cycles", wait_cycles),
        UVM_LOW)
  endtask



	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		`uvm_info("build_phase", "Entered...", UVM_HIGH)

		if (!uvm_config_db #(virtual phy_if)::get(this, "", "phy_vif", phy_vif))
			`uvm_fatal(get_type_name(), $sformatf("Failed to get phy_if"))
		if (!uvm_config_db #(virtual ahb_if)::get(this, "", "ahb_vif", ahb_vif))
			`uvm_fatal(get_type_name(), $sformatf("Failed to get ahb_if"))
		
			env = eth_environment::type_id::create("env", this);
			err_catcher = phy_error_catcher::type_id::create("err_catcher");
			cfg = phy_config::type_id::create("cfg");
			uvm_report_cb::add(null, err_catcher);

			uvm_config_db #(virtual phy_if)::set(this, "env", "phy_vif", phy_vif);
			uvm_config_db #(virtual ahb_if)::set(this, "env", "ahb_vif", ahb_vif);
			uvm_config_db #(phy_config)::set(this, "env", "phy_cfg", cfg);

		uvm_top.set_timeout(usr_timeout);
		`uvm_info("build_phase", "Exitting...", UVM_HIGH)
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		this.regmodel = env.regmodel;
	endfunction

	virtual function void end_of_elaboration_phase(uvm_phase phase);
		super.end_of_elaboration_phase(phase);
		uvm_top.print_topology();
	endfunction

	virtual function void final_phase(uvm_phase phase);
		super.final_phase(phase);
		`uvm_info("final_phase", "Entered...", UVM_HIGH)
		svr = uvm_report_server::get_server();
		if(svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR)) begin
			`uvm_info(get_type_name(), "--------------------------------", UVM_NONE)
			`uvm_info(get_type_name(), "----	TEST FAILED	----", UVM_NONE)
			`uvm_info(get_type_name(), "--------------------------------", UVM_NONE)
		end
		else begin
			`uvm_info(get_type_name(), "--------------------------------", UVM_NONE)
			`uvm_info(get_type_name(), "----	TEST PASSED	----", UVM_NONE)
			`uvm_info(get_type_name(), "--------------------------------", UVM_NONE)
		end

		`uvm_info("final_phase", "Exitting...", UVM_HIGH)
	endfunction
endclass
