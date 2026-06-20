class eth_TX_DATA_reg extends uvm_reg;
  `uvm_object_utils(eth_TX_DATA_reg)

  rand uvm_reg_field TX_DATA;
  
  function new(string name="eth_TX_DATA_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    TX_DATA = uvm_reg_field::type_id::create("TX_DATA");

    TX_DATA.configure(this, 32, 0, "WO", 1'b0, 32'h00000000, 0, 1, 1);
  endfunction
endclass

