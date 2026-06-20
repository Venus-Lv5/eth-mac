class eth_TX_LEN_reg extends uvm_reg;
  `uvm_object_utils(eth_TX_LEN_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field TX_LEN;
  
  function new(string name="eth_TX_LEN_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    TX_LEN = uvm_reg_field::type_id::create("TX_LEN");

    rsvd.configure(this, 16, 16, "RO", 1'b0, 16'h0000, 1, 1, 1);
    TX_LEN.configure(this, 16, 0, "RW", 1'b0, 16'h0000, 1, 1, 1);
  endfunction
endclass

