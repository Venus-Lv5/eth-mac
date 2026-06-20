class eth_RX_LEN_reg extends uvm_reg;
  `uvm_object_utils(eth_RX_LEN_reg)

  uvm_reg_field rsvd;
  uvm_reg_field RX_LEN;
  
  function new(string name="eth_RX_LEN_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    RX_LEN = uvm_reg_field::type_id::create("RX_LEN");

    rsvd.configure(this, 16, 16, "RO", 1'b0, 16'h0000, 1, 1, 1);
    RX_LEN.configure(this, 16, 0, "RO", 1'b0, 16'h0000, 0, 1, 1);
  endfunction
endclass

