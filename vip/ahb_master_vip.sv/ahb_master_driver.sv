class ahb_master_driver extends uvm_driver #(ahb_master_transaction);
  `uvm_component_utils(ahb_master_driver)

  virtual ahb_master_if ahb_m_vif;

  function new(string name="ahb_driver", uvm_component parent);
    super.new(name, parent);
  endfunction //new()

  virtual function void build_phase (uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual ahb_master_if)::get(this, "", "ahb_m_vif", ahb_m_vif))
      `uvm_fatal(get_type_name(), $sformat("Failed to get from uvm_config_db. Please check!"))
  endfunction

  virtual task run_phase(uvm_phase phase);
    ahb_master_transaction seq, rsp;

    wait (ahb_m_vif.HRESETn == 1);

    forever begin
      uvm_sequence_port.next_item(seq);

      // Phase 1
      @(posedge ahb_m_vif.HCLK);
      ahb_m_vif.HADDR       <= seq.addr;
      ahb_m_vif.HWRITE      <= seq.xact_type;
      ahb_m_vif.HBURST      <= seq.burst_type;
      ahb_m_vif.HSIZE       <= seq.xfer_size;
      ahb_m_vif.HPROT       <= seq.prot;
      ahb_m_vif.HMASTLOCK   <= seq.lock;
      ahb_m_vif.HTRANS      <= 2'h2;

      `uvm_info("run_phase", $sformatf("Start %s transaction - ADRRESS: 0x%0h", seq.xact_type ? "WRITE" : "READ", seq.addr), UVM_LOW);

    // Phase 2
      @(posedge ahb_m_vif.HCLK);
      ahb_m_vif.HADDR       <= 0;
      ahb_m_vif.HWRITE      <= 0;
      ahb_m_vif.HBURST      <= 0;
      ahb_m_vif.HSIZE       <= 0;
      ahb_m_vif.HPROT       <= 0;
      ahb_m_vif.HMASTLOCK   <= 0;
      ahb_m_vif.HTRANS      <= 0;

      if (xact_type == ahb_master_transaction::WRITE) begin
        ahb_m_vif.HWDATA    <= seq.data;
      end
      @(posedge ahb_m_vif.HREADYOUT);
      if (xact_type == ahb_master_transaction::READ) begin
        seq.data            <= ahb_m_vif.HRDATA;
      end

      $cast(rsp, seq.clone());
      rsp.set_id_info(seq);
      uvm_sequence_port.put(rsp);

      `uvm_info("run_phase", $sformatf("Completed %s transaction at addr 0x%0h and data: 0x%0h", seq.xact_type ? "WRITE" : "READ", seq.addr, seq.data), UVM_LOW);

      seq_item_port.item_done90;
    end
  endtask: run_phase

endclass: ahb_master_driver