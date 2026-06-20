class ahb_driver extends uvm_driver #(ahb_transaction);
  `uvm_component_utils(ahb_driver)

  virtual ahb_if ahb_vif;

  function new(string name="ahb_driver", uvm_component parent);
    super.new(name,parent);
  endfunction: new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    /** Applying the virtual interface received through the config db - learn detail in next session*/
    if(!uvm_config_db#(virtual ahb_if)::get(this,"","ahb_vif",ahb_vif))
      `uvm_fatal(get_type_name(),$sformatf("Failed to get from uvm_config_db. Please check!"))
  endfunction: build_phase

  virtual task run_phase(uvm_phase phase);
    ahb_transaction seq, rsp;

    drive_idle();
    wait(ahb_vif.HRESETn == 1);
    @(posedge ahb_vif.HCLK);

    forever begin
      seq_item_port.get_next_item(seq);
      seq.apply_compat_fields();

      `uvm_info("run_phase", $sformatf("Start %s transaction - ADRRESS: 0x%0h",
                 seq.xact_type ? "WRITE" : "READ", seq.addr), UVM_LOW);

      drive_transaction(seq);

      $cast(rsp, seq.clone());
      rsp.rdata_q = seq.rdata_q;
      rsp.resp_q  = seq.resp_q;
      rsp.data    = seq.data;
      rsp.rdata   = seq.rdata;
      rsp.wdata   = seq.wdata;
      rsp.write   = seq.write;
      rsp.beat_rdata = seq.beat_rdata;
      rsp.beat_resp  = seq.beat_resp;
      rsp.resp    = seq.resp;
      rsp.set_id_info(seq);

      seq_item_port.put(rsp);

      `uvm_info("run_phase", $sformatf("Completed %s transaction at addr 0x%0h and data: 0x%0h",
                 seq.xact_type ? "WRITE" : "READ", seq.addr, seq.data), UVM_LOW);

      seq_item_port.item_done();
    end

  endtask: run_phase

  virtual task drive_transaction(ahb_transaction seq);
    int unsigned beats;

    seq.apply_compat_fields();
    beats = seq.get_burst_len();
    seq.rdata_q.delete();
    seq.resp_q.delete();
    seq.beat_rdata.delete();
    seq.beat_resp.delete();

    if (!validate_transaction(seq, beats)) begin
      seq.resp = ahb_transaction::HRESP_ERROR;
      seq.resp_q.push_back(ahb_transaction::HRESP_ERROR);
      seq.update_compat_fields();
      drive_idle();
      return;
    end

    repeat (seq.idle_cycles) begin
      drive_idle();
      wait_hready();
    end

    drive_address_phase(seq, 0, ahb_transaction::HTRANS_NONSEQ);
    wait_hready();

    for (int unsigned beat = 1; beat < beats; beat++) begin
      drive_data_phase(seq, beat - 1);
      drive_address_phase(seq, beat, ahb_transaction::HTRANS_SEQ);
      wait_hready();
      complete_data_phase(seq, beat - 1);
    end

    drive_data_phase(seq, beats - 1);
    drive_idle(1'b0);
    wait_hready();
    complete_data_phase(seq, beats - 1);
    drive_idle();
    seq.update_compat_fields();
  endtask: drive_transaction

  virtual function bit validate_transaction(ahb_transaction seq, int unsigned beats);
    int unsigned fixed_len;

    if (beats == 0) begin
      `uvm_error(get_type_name(), "AHB transaction has zero beats")
      return 0;
    end

    if (seq.get_xfer_bytes() > (`AHB_DATA_WIDTH/8)) begin
      `uvm_error(get_type_name(), $sformatf("Unsupported HSIZE %0s for DATA_WIDTH=%0d",
                 seq.xfer_size.name(), `AHB_DATA_WIDTH))
      return 0;
    end

    if (!seq.is_aligned()) begin
      `uvm_error(get_type_name(), $sformatf("Misaligned AHB address for size %0s: %s",
                 seq.xfer_size.name(), seq.convert2string()))
      return 0;
    end

    fixed_len = get_fixed_burst_len(seq.burst_type);
    if ((fixed_len != 0) && (beats != fixed_len)) begin
      `uvm_error(get_type_name(), $sformatf("Burst %0s requires %0d beats, got %0d",
                 seq.burst_type.name(), fixed_len, beats))
      return 0;
    end

    if ((seq.burst_type == ahb_transaction::HBURST_SINGLE) && (beats != 1)) begin
      `uvm_error(get_type_name(), $sformatf("SINGLE burst cannot carry %0d beats", beats))
      return 0;
    end

    return 1;
  endfunction: validate_transaction

  virtual function int unsigned get_fixed_burst_len(ahb_transaction::hburst_e burst_type);
    case (burst_type)
      ahb_transaction::HBURST_WRAP4,
      ahb_transaction::HBURST_INCR4:  return 4;
      ahb_transaction::HBURST_WRAP8,
      ahb_transaction::HBURST_INCR8:  return 8;
      ahb_transaction::HBURST_WRAP16,
      ahb_transaction::HBURST_INCR16: return 16;
      default:                        return 0;
    endcase
  endfunction: get_fixed_burst_len

  virtual task wait_hready();
    do begin
      @(posedge ahb_vif.HCLK);
    end while ((ahb_vif.HRESETn === 1'b1) && (ahb_vif.HREADYOUT !== 1'b1));
  endtask: wait_hready

  virtual task drive_idle(bit clear_wdata = 1'b1);
    ahb_vif.HSEL       <= 1'b0;
    ahb_vif.HADDR      <= '0;
    ahb_vif.HWRITE     <= 1'b0;
    ahb_vif.HBURST     <= ahb_transaction::HBURST_SINGLE;
    ahb_vif.HSIZE      <= ahb_transaction::HSIZE_WORD;
    ahb_vif.HPROT      <= 4'h0;
    ahb_vif.HMASTLOCK  <= 1'b0;
    ahb_vif.HTRANS     <= ahb_transaction::HTRANS_IDLE;
    if (clear_wdata)
      ahb_vif.HWDATA   <= '0;
  endtask: drive_idle

  virtual task drive_address_phase(ahb_transaction seq, int unsigned beat, ahb_transaction::htrans_e htrans);
    ahb_vif.HSEL       <= 1'b1;
    ahb_vif.HADDR      <= seq.get_beat_addr(beat);
    ahb_vif.HWRITE     <= (seq.xact_type == ahb_transaction::WRITE);
    ahb_vif.HBURST     <= seq.burst_type;
    ahb_vif.HSIZE      <= seq.xfer_size;
    ahb_vif.HPROT      <= seq.prot;
    ahb_vif.HMASTLOCK  <= seq.lock;
    ahb_vif.HTRANS     <= htrans;
  endtask: drive_address_phase

  virtual task drive_data_phase(ahb_transaction seq, int unsigned beat);
    if (seq.xact_type == ahb_transaction::WRITE)
      ahb_vif.HWDATA <= seq.get_beat_wdata(beat);
    else
      ahb_vif.HWDATA <= '0;
  endtask: drive_data_phase

  virtual task complete_data_phase(ahb_transaction seq, int unsigned beat);
    while (seq.rdata_q.size() <= beat)
      seq.rdata_q.push_back('0);
    while (seq.resp_q.size() <= beat)
      seq.resp_q.push_back(ahb_transaction::HRESP_OKAY);

    seq.resp_q[beat] = ahb_transaction::hresp_e'(ahb_vif.HRESP);
    seq.resp = ahb_transaction::hresp_e'(ahb_vif.HRESP);

    if (seq.xact_type == ahb_transaction::READ) begin
      seq.rdata_q[beat] = ahb_vif.HRDATA;
      if (beat == 0)
        seq.data = ahb_vif.HRDATA;
    end

    if (ahb_transaction::hresp_e'(ahb_vif.HRESP) == ahb_transaction::HRESP_ERROR) begin
      `uvm_error(get_type_name(), $sformatf("AHB ERROR response on beat %0d: addr=0x%0h write=%0b data=0x%0h",
                 beat, seq.get_beat_addr(beat), (seq.xact_type == ahb_transaction::WRITE),
                 (seq.xact_type == ahb_transaction::WRITE) ? seq.get_beat_wdata(beat) : ahb_vif.HRDATA))
    end
  endtask: complete_data_phase

endclass: ahb_driver
