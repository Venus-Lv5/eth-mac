class eth_MAC_SA_HIGH_reg extends uvm_reg;
  `uvm_object_utils(eth_MAC_SA_HIGH_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field MAC_SA_HIGH;
  
  function new(string name="eth_MAC_SA_HIGH_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    MAC_SA_HIGH = uvm_reg_field::type_id::create("MAC_SA_HIGH");

    rsvd.configure(this, 16, 16, "RO", 1'b0, 16'h0000, 1, 1, 1);
    MAC_SA_HIGH.configure(this, 16, 0, "RW", 1'b0, 16'h0000, 1, 1, 1);
  endfunction
endclass

