class ahb_monitor extends uvm_monitor;
  `uvm_component_utils(ahb_monitor)
  uvm_analysis_port #(ahb_transaction) mon_ap;
  uvm_analysis_port #(ahb_transaction) ahb_observe_port;
  virtual ahb_if ahb_vif;

  bit                          pipe_valid;
  bit[`AHB_ADDR_WIDTH-1:0]     pipe_addr;
  bit                          pipe_write;
  ahb_transaction::hsize_e     pipe_size;
  ahb_transaction::hburst_e    pipe_burst;
  bit[3:0]                     pipe_prot;
  bit                          pipe_lock;
  ahb_transaction::htrans_e    pipe_htrans;
  int unsigned                 pipe_beat_index;
  int unsigned                 pipe_burst_len;
  int unsigned                 burst_beat_index;
  int unsigned                 burst_len;
 
  function new(string name="ahb_monitor", uvm_component parent);
    super.new(name,parent);
  endfunction: new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    ahb_observe_port = new("ahb_observe_port", this);
    mon_ap = ahb_observe_port;
    if (!uvm_config_db #(virtual ahb_if)::get(this, "", "ahb_vif", ahb_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get ahb_vif"));
    
  endfunction: build_phase

  virtual task run_phase(uvm_phase phase);
    bit                      sample_resetn;
    bit                      sample_ready;
    bit                      sample_hsel;
    bit[`AHB_ADDR_WIDTH-1:0] sample_addr;
    bit                      sample_write;
    ahb_transaction::hsize_e  sample_size;
    ahb_transaction::hburst_e sample_burst;
    bit[3:0]                 sample_prot;
    bit                      sample_lock;
    ahb_transaction::htrans_e sample_htrans;
    bit[`AHB_DATA_WIDTH-1:0] sample_wdata;
    bit[`AHB_DATA_WIDTH-1:0] sample_rdata;
    ahb_transaction::hresp_e sample_resp;

    pipe_valid      = 1'b0;
    burst_beat_index = 0;
    burst_len       = 0;

    forever begin
      @(posedge ahb_vif.HCLK);
      sample_resetn = ahb_vif.HRESETn;
      sample_ready  = ahb_vif.HREADYOUT;
      sample_hsel   = ahb_vif.HSEL;
      sample_addr   = ahb_vif.HADDR;
      sample_write  = ahb_vif.HWRITE;
      sample_size   = ahb_transaction::hsize_e'(ahb_vif.HSIZE);
      sample_burst  = ahb_transaction::hburst_e'(ahb_vif.HBURST);
      sample_prot   = ahb_vif.HPROT;
      sample_lock   = ahb_vif.HMASTLOCK;
      sample_htrans = ahb_transaction::htrans_e'(ahb_vif.HTRANS);
      sample_wdata  = ahb_vif.HWDATA;
      sample_rdata  = ahb_vif.HRDATA;
      sample_resp   = ahb_transaction::hresp_e'(ahb_vif.HRESP);

      if (sample_resetn !== 1'b1) begin
        pipe_valid       = 1'b0;
        burst_beat_index = 0;
        burst_len        = 0;
        continue;
      end

      if (sample_ready === 1'b1) begin
        if (pipe_valid)
          publish_data_phase(sample_wdata, sample_rdata, sample_resp);

        capture_address_phase(sample_hsel,
                              sample_addr,
                              sample_write,
                              sample_size,
                              sample_burst,
                              sample_prot,
                              sample_lock,
                              sample_htrans);
      end
    end
  endtask: run_phase

  virtual task publish_data_phase(bit[`AHB_DATA_WIDTH-1:0] sample_wdata,
                                  bit[`AHB_DATA_WIDTH-1:0] sample_rdata,
                                  ahb_transaction::hresp_e sample_resp);
    ahb_transaction trans;

    trans = ahb_transaction::type_id::create("trans");
    trans.addr = pipe_addr;
    trans.xact_type = pipe_write ? ahb_transaction::WRITE : ahb_transaction::READ;
    trans.prot = pipe_prot;
    trans.lock = pipe_lock;
    trans.htrans = pipe_htrans;
    trans.beat_index = pipe_beat_index;
    trans.num_beats = pipe_burst_len;
    trans.xfer_size = pipe_size;
    trans.burst_type = pipe_burst;
    trans.beat_addr.push_back(pipe_addr);

    if (pipe_write) begin
      trans.data = sample_wdata;
      trans.wdata = sample_wdata;
      trans.wdata_q.push_back(sample_wdata);
      trans.beat_wdata.push_back(sample_wdata);
    end
    else begin
      trans.data = sample_rdata;
      trans.rdata = sample_rdata;
      trans.rdata_q.push_back(sample_rdata);
      trans.beat_rdata.push_back(sample_rdata);
    end

    trans.write = pipe_write;
    trans.size = pipe_size;
    trans.burst = pipe_burst;
    trans.trans = pipe_htrans;
    trans.resp = sample_resp;
    trans.resp_q.push_back(sample_resp);
    trans.beat_resp.push_back(sample_resp);

    if (sample_resp == ahb_transaction::HRESP_ERROR) begin
      `uvm_error(get_type_name(), $sformatf("AHB ERROR response observed on beat %0d: addr=0x%0h write=%0b data=0x%0h",
                 pipe_beat_index, trans.addr, pipe_write, trans.data))
    end

    `uvm_info("ahb_monitor", $sformatf("Send trans from monitor to scoreboard: \n%s", trans.sprint()), UVM_LOW);
    ahb_observe_port.write(trans);
  endtask: publish_data_phase

  virtual function void capture_address_phase(bit sample_hsel,
                                              bit[`AHB_ADDR_WIDTH-1:0] sample_addr,
                                              bit sample_write,
                                              ahb_transaction::hsize_e sample_size,
                                              ahb_transaction::hburst_e sample_burst,
                                              bit[3:0] sample_prot,
                                              bit sample_lock,
                                              ahb_transaction::htrans_e sample_htrans);
    pipe_valid = 1'b0;

    if ((sample_hsel !== 1'b1) ||
        !((sample_htrans == ahb_transaction::HTRANS_NONSEQ) || (sample_htrans == ahb_transaction::HTRANS_SEQ))) begin
      if (sample_htrans == ahb_transaction::HTRANS_IDLE)
        burst_beat_index = 0;
      return;
    end

    if (sample_htrans == ahb_transaction::HTRANS_NONSEQ) begin
      burst_beat_index = 0;
      burst_len = get_burst_len(sample_burst);
    end
    else begin
      burst_beat_index++;
    end

    pipe_valid     = 1'b1;
    pipe_addr      = sample_addr;
    pipe_write     = sample_write;
    pipe_size      = sample_size;
    pipe_burst     = sample_burst;
    pipe_prot      = sample_prot;
    pipe_lock      = sample_lock;
    pipe_htrans    = sample_htrans;
    pipe_beat_index = burst_beat_index;
    pipe_burst_len = burst_len;
  endfunction: capture_address_phase

  virtual function int unsigned get_burst_len(ahb_transaction::hburst_e burst_type);
    case (burst_type)
      ahb_transaction::HBURST_SINGLE: return 1;
      ahb_transaction::HBURST_WRAP4,
      ahb_transaction::HBURST_INCR4:  return 4;
      ahb_transaction::HBURST_WRAP8,
      ahb_transaction::HBURST_INCR8:  return 8;
      ahb_transaction::HBURST_WRAP16,
      ahb_transaction::HBURST_INCR16: return 16;
      default:                        return 0;
    endcase
  endfunction: get_burst_len

endclass: ahb_monitor
