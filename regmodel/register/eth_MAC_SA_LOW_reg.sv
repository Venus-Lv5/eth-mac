class eth_MAC_SA_LOW_reg extends uvm_reg;
  `uvm_object_utils(eth_MAC_SA_LOW_reg)

  rand uvm_reg_field MAC_SA_LOW;
  
  function new(string name="eth_MAC_SA_LOW_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    MAC_SA_LOW = uvm_reg_field::type_id::create("MAC_SA_LOW");

    MAC_SA_LOW.configure(this, 32, 0, "RW", 1'b0, 32'h00000000, 1, 1, 1);
  endfunction
endclass

