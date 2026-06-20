class eth_IER_reg extends uvm_reg;
  `uvm_object_utils(eth_IER_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field RX_PAUSE_SEEN_IE;
  rand uvm_reg_field RX_ERR_IE;
  rand uvm_reg_field RX_BUSY_IE;
  rand uvm_reg_field RX_AVAIL_IE;
  rand uvm_reg_field TX_ERR_IE;
  rand uvm_reg_field TX_DONE_IE;
  
  function new(string name="eth_IER_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    RX_PAUSE_SEEN_IE = uvm_reg_field::type_id::create("RX_PAUSE_SEEN_IE");
    RX_ERR_IE = uvm_reg_field::type_id::create("RX_ERR_IE");
    RX_BUSY_IE = uvm_reg_field::type_id::create("RX_BUSY_IE");
    RX_AVAIL_IE = uvm_reg_field::type_id::create("RX_AVAIL_IE");
    TX_ERR_IE = uvm_reg_field::type_id::create("TX_ERR_IE");
    TX_DONE_IE = uvm_reg_field::type_id::create("TX_DONE_IE");

    rsvd.configure(this, 26, 6, "RO", 1'b0, 26'h0000000, 1, 1, 1);
    RX_PAUSE_SEEN_IE.configure(this, 1, 5, "RW", 1'b0, 1'b0, 1, 1, 1);
    RX_ERR_IE.configure(this, 1, 4, "RW", 1'b0, 1'b0, 1, 1, 1);
    RX_BUSY_IE.configure(this, 1, 3, "RW", 1'b0, 1'b0, 1, 1, 1);
    RX_AVAIL_IE.configure(this, 1, 2, "RW", 1'b0, 1'b0, 1, 1, 1);
    TX_ERR_IE.configure(this, 1, 1, "RW", 1'b0, 1'b0, 1, 1, 1);
    TX_DONE_IE.configure(this, 1, 0, "RW", 1'b0, 1'b0, 1, 1, 1);
  endfunction
endclass

