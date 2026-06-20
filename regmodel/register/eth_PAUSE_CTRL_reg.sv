class eth_PAUSE_CTRL_reg extends uvm_reg;
  `uvm_object_utils(eth_PAUSE_CTRL_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field RX_PAUSE_EN;
  rand uvm_reg_field TX_PAUSE_EN;
  
  function new(string name="eth_PAUSE_CTRL_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    RX_PAUSE_EN = uvm_reg_field::type_id::create("RX_PAUSE_EN");
    TX_PAUSE_EN = uvm_reg_field::type_id::create("TX_PAUSE_EN");

    rsvd.configure(this, 30, 2, "RO", 1'b0, 30'h00000000, 1, 1, 1);
    RX_PAUSE_EN.configure(this, 1, 1, "RW", 1'b0, 1'b1, 1, 1, 1);
    TX_PAUSE_EN.configure(this, 1, 0, "RW", 1'b0, 1'b1, 1, 1, 1);
  endfunction
endclass

