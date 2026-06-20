class eth_environment extends uvm_env;
  `uvm_component_utils(eth_environment)

  virtual phy_if phy_vif;
  virtual ahb_if ahb_vif;

  phy_config phy_cfg;
  // ahb_config ahb_cfg;

  eth_scoreboard sb;
  phy_agent phy_agt;
  ahb_agent ahb_agt;

  eth_reg_block regmodel;
  eth_reg2ahb_adapter ahb_adapter;
  uvm_reg_predictor #(ahb_transaction) ahb_predictor;

  function new(string name = "eth_environment", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("build_phase", "Entered...", UVM_HIGH)

    if(!uvm_config_db #(virtual ahb_if)::get(this, "", "ahb_vif", ahb_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get ahb_if"))
    if(!uvm_config_db #(virtual phy_if)::get(this, "", "phy_vif", phy_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get phy_if"))
    if(!uvm_config_db #(phy_config)::get(this, "", "phy_cfg", phy_cfg))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get phy_config"))
    // if(!uvm_config_db #(ahb_config)::get(this, "", "ahb_cfg", ahb_cfg))
    //   `uvm_fatal(get_type_name(), $sformatf("Failed to get ahb_config"))

    ahb_agt = ahb_agent::type_id::create("ahb_agt", this);
    phy_agt = phy_agent::type_id::create("phy_agt", this);
    sb = eth_scoreboard::type_id::create("sb", this);

    ahb_adapter = eth_reg2ahb_adapter::type_id::create("ahb_adapter");
    regmodel = eth_reg_block::type_id::create("regmodel", this);
    regmodel.build();

    ahb_predictor = uvm_reg_predictor #(ahb_transaction)::type_id::create("ahb_predictor", this);

    uvm_config_db #(virtual phy_if)::set(this, "phy_agt", "phy_vif", phy_vif);
    uvm_config_db #(virtual ahb_if)::set(this, "ahb_agt", "ahb_vif", ahb_vif);
    uvm_config_db #(phy_config)::set(this, "phy_agt", "cfg", phy_cfg);
    //uvm_config_db #(ahb_config)::set(this, "ahb_agt", "cfg", ahb_cfg);
    uvm_config_db #(phy_config)::set(this, "sb", "phy_cfg", phy_cfg);
    //uvm_config_db #(ahb_config)::set(this, "sb", "ahb_cfg", ahb_cfg);

    `uvm_info("build_phase", "Exitting...", UVM_HIGH)
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info("connect_phase", "Entered...", UVM_HIGH)

    if (regmodel.get_parent() == null)
      regmodel.ahb_map.set_sequencer(ahb_agt.sequencer, ahb_adapter);

    ahb_predictor.map = regmodel.ahb_map;
    ahb_predictor.adapter = ahb_adapter;
    ahb_agt.monitor.ahb_observe_port.connect(ahb_predictor.bus_in);

    phy_agt.monitor.phy_observe_port_tx.connect(sb.phy_tx_export);
    phy_agt.monitor.phy_observe_port_rx.connect(sb.phy_rx_export);
    ahb_agt.monitor.ahb_observe_port.connect(sb.ahb_export);

    `uvm_info("connect_phase", "Exiting...", UVM_HIGH)
  endfunction

endclass