class eth_HASH_0_reg extends uvm_reg;
  `uvm_object_utils(eth_HASH_0_reg)

  rand uvm_reg_field HASH_0;
  
  function new(string name="eth_HASH_0_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    HASH_0 = uvm_reg_field::type_id::create("HASH_0");

    HASH_0.configure(this, 32, 0, "RW", 1'b0, 32'h00000000, 1, 1, 1);
  endfunction
endclass

