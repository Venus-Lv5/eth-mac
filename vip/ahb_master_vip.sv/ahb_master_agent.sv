class ahb_master_agent extends uvm_agent;
  `uvm_component_utils(ahb_master_agent)

  ahb_master_sequencer    sequencer;
  ahb_master_driver       driver;
  ahb_master_monitor      monitor;

  virtual ahb_master_if   ahb_m_vif;

  function new (string name="ahb_master_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(virtual ahb_master_if)::get(this, "", "ahb_m_vif"))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get ahb_m_vif"));
    
    if (is_active == UVM_ACTIVE) begin
      `uvm_info(get_type_name(),$sformatf("Active agent is configued"),UVM_LOW)
      sequencer   = ahb_master_sequencer::type_id::create("sequencer", this);
      driver      = ahb_master_driver::type_id::create("driver", this);
      monitor     = ahb_master_monitor::type_id::create("monitor", this);

      uvm_config_db #(virtual ahb_master_if)::set(this, "driver", "ahb_m_vif", ahb_vif);
      uvm_config_db #(virtual ahb_master_if)::set(this, "monitor", "ahb_m_vif", ahb_vif);
    end
    else begin
      `uvm_info(get_type_name(),$sformatf("Passive agent is configued"),UVM_LOW)

      monitor     = ahb_master_monitor::type_id::create("monitor", this);
      uvm_config_db #(virtual ahb_master_if)::set(this, "monitor", "ahb_m_vif", ahb_vif);
    end

  endfunction: build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if(get_is_active() == UVM_ACTIVE) begin 
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction: connect_phase

endclass: ahb_master_agent