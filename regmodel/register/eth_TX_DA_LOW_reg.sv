class eth_TX_DA_LOW_reg extends uvm_reg;
  `uvm_object_utils(eth_TX_DA_LOW_reg)

  rand uvm_reg_field TX_DA_LOW;
  
  function new(string name="eth_TX_DA_LOW_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    TX_DA_LOW = uvm_reg_field::type_id::create("TX_DA_LOW");

    TX_DA_LOW.configure(this, 32, 0, "RW", 1'b0, 32'h00000000, 1, 1, 1);
  endfunction
endclass

