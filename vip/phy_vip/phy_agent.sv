class phy_agent extends uvm_agent;
  `uvm_component_utils(phy_agent)

  virtual phy_if phy_vif;
  phy_config     cfg;

  phy_sequencer  sequencer;
  phy_driver     driver;
  phy_monitor    monitor;

  function new(string name="phy_agent", uvm_component parent);
    super.new(name, parent);
  endfunction: new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(virtual phy_if)::get(this, "", "phy_vif", phy_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get phy_if"))

    if (!uvm_config_db #(phy_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get cfg"))

    if (is_active == UVM_ACTIVE) begin
      `uvm_info(get_type_name(), $sformatf("Active agent is configured"), UVM_LOW)

      sequencer = phy_sequencer::type_id::create("sequencer", this);
      driver    = phy_driver::type_id::create("driver", this);

      uvm_config_db #(virtual phy_if)::set(this, "driver",    "phy_vif", phy_vif);

      uvm_config_db #(phy_config)::set(this, "driver",    "cfg", cfg);
    end
    else begin
      `uvm_info(get_type_name(), $sformatf("Passive agent is configured"), UVM_LOW)
    end

    monitor = phy_monitor::type_id::create("monitor", this);
    uvm_config_db #(virtual phy_if)::set(this, "monitor", "phy_vif", phy_vif);
    uvm_config_db #(phy_config)::set(this, "monitor", "cfg", cfg);
  endfunction: build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction: connect_phase

endclass: phy_agent
