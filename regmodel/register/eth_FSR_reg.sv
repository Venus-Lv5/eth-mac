class eth_FSR_reg extends uvm_reg;
  `uvm_object_utils(eth_FSR_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field RX_PAUSE_SEEN;
  uvm_reg_field RX_PAUSE_ACTIVE;
  uvm_reg_field TX_PAUSE_REQ;
  rand uvm_reg_field RX_ERR;
  rand uvm_reg_field RX_BUSY;
  uvm_reg_field RX_AVAIL;
  rand uvm_reg_field TX_ERR;
  rand uvm_reg_field TX_DONE;
  uvm_reg_field TX_BUSY;
  uvm_reg_field TX_READY;
  
  function new(string name="eth_FSR_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    RX_PAUSE_SEEN = uvm_reg_field::type_id::create("RX_PAUSE_SEEN");
    RX_PAUSE_ACTIVE = uvm_reg_field::type_id::create("RX_PAUSE_ACTIVE");
    TX_PAUSE_REQ = uvm_reg_field::type_id::create("TX_PAUSE_REQ");
    RX_ERR = uvm_reg_field::type_id::create("RX_ERR");
    RX_BUSY = uvm_reg_field::type_id::create("RX_BUSY");
    RX_AVAIL = uvm_reg_field::type_id::create("RX_AVAIL");
    TX_ERR = uvm_reg_field::type_id::create("TX_ERR");
    TX_DONE = uvm_reg_field::type_id::create("TX_DONE");
    TX_BUSY = uvm_reg_field::type_id::create("TX_BUSY");
    TX_READY = uvm_reg_field::type_id::create("TX_READY");

    rsvd.configure(this, 22, 10, "RO", 1'b0, 22'h000000, 1, 0, 1);
    RX_PAUSE_SEEN.configure(this, 1, 9, "W1C", 1'b1, 1'b0, 1, 0, 1);
    RX_PAUSE_ACTIVE.configure(this, 1, 8, "RO", 1'b1, 1'b0, 1, 0, 1);
    TX_PAUSE_REQ.configure(this, 1, 7, "RO", 1'b1, 1'b0, 1, 0, 1);
    RX_ERR.configure(this, 1, 6, "W1C", 1'b1, 1'b0, 1, 0, 1);
    RX_BUSY.configure(this, 1, 5, "W1C", 1'b1, 1'b0, 1, 0, 1);
    RX_AVAIL.configure(this, 1, 4, "RO", 1'b1, 1'b0, 1, 0, 1);
    TX_ERR.configure(this, 1, 3, "W1C", 1'b1, 1'b0, 1, 0, 1);
    TX_DONE.configure(this, 1, 2, "W1C", 1'b1, 1'b0, 1, 0, 1);
    TX_BUSY.configure(this, 1, 1, "RO", 1'b1, 1'b0, 1, 0, 1);
    TX_READY.configure(this, 1, 0, "RO", 1'b1, 1'b0, 1, 0, 1);
  endfunction
endclass
