class eth_ahb_burst_write_seq extends uvm_sequence #(ahb_transaction);
  `uvm_object_utils(eth_ahb_burst_write_seq)

  bit[`AHB_ADDR_WIDTH-1:0]    start_addr;
  bit[`AHB_ADDR_WIDTH-1:0]    end_addr;
  bit[`AHB_DATA_WIDTH-1:0]    data_q[$];
  bit                         auto_fixed_burst;

  function new(string name="eth_ahb_burst_write_seq");
    super.new(name);
    auto_fixed_burst = 1'b1;
  endfunction

  virtual task body();
    ahb_transaction req;
    ahb_transaction rsp;
    int unsigned access_bytes;
    int unsigned total_beats;
    int unsigned sent_beats;
    int unsigned chunk_beats;

    access_bytes = (1 << ahb_transaction::SIZE_32BIT);
    total_beats = ((end_addr - start_addr) / access_bytes) + 1;
    sent_beats = 0;

    while (sent_beats < total_beats) begin
      chunk_beats = choose_chunk_beats(total_beats - sent_beats);
      req = ahb_transaction::type_id::create($sformatf("ahb_burst_write_%0d", sent_beats));

      start_item(req);
      fill_req(req, sent_beats, chunk_beats, access_bytes);
      finish_item(req);

      get_response(rsp);
      check_rsp(rsp, sent_beats, chunk_beats, access_bytes);
      sent_beats += chunk_beats;
    end
  endtask

  local function int unsigned choose_chunk_beats(int unsigned remaining_beats);
    if (auto_fixed_burst) begin
      if (remaining_beats >= 16)
        return 16;
      if (remaining_beats >= 8)
        return 8;
      if (remaining_beats >= 4)
        return 4;
    end
    return remaining_beats;
  endfunction

  local function ahb_transaction::hburst_e choose_burst(int unsigned beats);
    if (auto_fixed_burst) begin
      if (beats == 16)
        return ahb_transaction::HBURST_INCR16;
      if (beats == 8)
        return ahb_transaction::HBURST_INCR8;
      if (beats == 4)
        return ahb_transaction::HBURST_INCR4;
    end
    if (beats == 1)
      return ahb_transaction::HBURST_SINGLE;
    return ahb_transaction::HBURST_INCR;
  endfunction

  local function void fill_req(ref ahb_transaction req,
                               int unsigned sent_beats,
                               int unsigned chunk_beats,
                               int unsigned access_bytes);
    bit[`AHB_ADDR_WIDTH-1:0] chunk_addr;

    chunk_addr = start_addr + (sent_beats * access_bytes);

    req.xact_type = ahb_transaction::WRITE;
    req.write = 1'b1;
    req.addr = chunk_addr;
    req.data = data_q[sent_beats];
    req.wdata = data_q[sent_beats];
    req.xfer_size = ahb_transaction::SIZE_32BIT;
    req.size = ahb_transaction::SIZE_32BIT;
    req.burst_type = choose_burst(chunk_beats);
    req.burst = req.burst_type;
    req.num_beats = chunk_beats;
    req.prot = 4'h0;
    req.lock = 1'b0;
    req.htrans = ahb_transaction::HTRANS_NONSEQ;
    req.trans = ahb_transaction::HTRANS_NONSEQ;

    req.addr_q.delete();
    req.wdata_q.delete();
    req.beat_addr.delete();
    req.beat_wdata.delete();

    for (int unsigned beat = 0; beat < chunk_beats; beat++) begin
      req.addr_q.push_back(chunk_addr + (beat * access_bytes));
      req.wdata_q.push_back(data_q[sent_beats + beat]);
    end

    `uvm_info(get_type_name(),
      $sformatf("AHB burst write chunk: addr=0x%0h beats=%0d burst=%0s",
                chunk_addr, chunk_beats, req.burst_type.name()),
      UVM_LOW)
  endfunction

  local function void check_rsp(ahb_transaction rsp,
                                int unsigned sent_beats,
                                int unsigned chunk_beats,
                                int unsigned access_bytes);
    if (rsp == null) begin
      `uvm_error(get_type_name(), "AHB burst write got null response")
      return;
    end

    for (int unsigned beat = 0; beat < chunk_beats; beat++) begin
      if ((rsp.resp_q.size() <= beat) ||
          (rsp.resp_q[beat] != ahb_transaction::HRESP_OKAY)) begin
        `uvm_error(get_type_name(),
          $sformatf("AHB burst write response error at beat %0d addr=0x%0h",
                    sent_beats + beat,
                    start_addr + ((sent_beats + beat) * access_bytes)))
      end
    end
  endfunction
endclass
