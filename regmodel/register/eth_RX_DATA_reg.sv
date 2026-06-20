class eth_RX_DATA_reg extends uvm_reg;
  `uvm_object_utils(eth_RX_DATA_reg)

  uvm_reg_field RX_DATA;
  
  function new(string name="eth_RX_DATA_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    RX_DATA = uvm_reg_field::type_id::create("RX_DATA");

    RX_DATA.configure(this, 32, 0, "RO", 1'b0, 32'h00000000, 0, 1, 1);
  endfunction
endclass

