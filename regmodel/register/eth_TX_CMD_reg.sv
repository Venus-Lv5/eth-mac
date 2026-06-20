class eth_TX_CMD_reg extends uvm_reg;
  `uvm_object_utils(eth_TX_CMD_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field TX_START;
  
  function new(string name="eth_TX_CMD_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    TX_START = uvm_reg_field::type_id::create("TX_START");

    rsvd.configure(this, 31, 1, "WO", 1'b0, 31'h00000000, 0, 1, 1);
    TX_START.configure(this, 1, 0, "WO", 1'b0, 1'b0, 0, 1, 1);
  endfunction
endclass

