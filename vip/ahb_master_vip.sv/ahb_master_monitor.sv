class ahb_master_monitor extends uvm_monitor;
  `uvm_component_utils(ahb_master_monitor)

  uvm_analysis_port #(ahb_master_transaction) ahb_m_observe_port;
  virtual ahb_master_if                       ahb_m_vif;

  function new (string name="ahb_master_monitor", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase (uvm_phase phase);
    super.build_phase(phase);

    ahb_m_observe_port = new("ahb_m_observe_port", this);

    if (!uvm_config_db#(virtual ahb_master_if)::get(this, "", "ahb_m_vif", ahb_m_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get from uvm_config_db. Please check!Failed to get from uvm_config_db. Please check!"));

  endfunction: build_phase

  virtual task run_phase(uvm_phase phase);
    forever begin
      ahb_master_transaction trans;
      `uvm_info("ahb_master_monitor", $sformatf("Capturing data from DUT"), UVM_LOW);

      wait(ahb_m_vif.HTRANS != 0);
      trans = ahb_master_transaction::type_id::create("trans");

      trans.addr      = ahb_m_vif.HADDR;
      $cast(trans.xact_type, ahb_m_vif.HWRITE);
      trans.prot      = ahb_m_vif.HPROT;
      trans.lock      = ahb_m_vif.HMASTLOCK;
      $cast(trans.xfer_size, ahb_m_vif.HSIZE);
      $cast(trans.burst_type, ahb_m_vif.HBURST);

      @(posedge ahb_m_vif.HREADYOUT); #1;
      trans.data = trans.xact_type ? ahb_m_vif.HWDATA : ahb_m_vif.HRDATA;
      trans.resp = ahb_m_vif.HRESP;
      `uvm_info("ahb_master_monitor", "Finish", UVM_LOW);

      `uvm_info("ahb_master_monitor", $sformatf("Send trans to sb:\n%s", trans.sprint()), UVM_LOW);
      ahb_m_observe_port.write(trans);
    end
  endtask: run_phase

endclass: ahb_master_monitor