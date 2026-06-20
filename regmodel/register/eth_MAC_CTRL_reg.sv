class eth_MAC_CTRL_reg extends uvm_reg;
  `uvm_object_utils(eth_MAC_CTRL_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field FULL;
  rand uvm_reg_field PRO;
  rand uvm_reg_field FIL_EN;
  rand uvm_reg_field BRO;
  rand uvm_reg_field TX_EN;
  rand uvm_reg_field RX_EN;
  
  function new(string name="eth_MAC_CTRL_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    FULL = uvm_reg_field::type_id::create("FULL");
    PRO = uvm_reg_field::type_id::create("PRO");
    FIL_EN = uvm_reg_field::type_id::create("FIL_EN");
    BRO = uvm_reg_field::type_id::create("BRO");
    TX_EN = uvm_reg_field::type_id::create("TX_EN");
    RX_EN = uvm_reg_field::type_id::create("RX_EN");

    rsvd.configure(this, 26, 6, "RO", 1'b0, 26'h0000000, 1, 1, 1);
    FULL.configure(this, 1, 5, "RW", 1'b0, 1'b1, 1, 1, 1);
    PRO.configure(this, 1, 4, "RW", 1'b0, 1'b0, 1, 1, 1);
    FIL_EN.configure(this, 1, 3, "RW", 1'b0, 1'b0, 1, 1, 1);
    BRO.configure(this, 1, 2, "RW", 1'b0, 1'b0, 1, 1, 1);
    TX_EN.configure(this, 1, 1, "RW", 1'b0, 1'b0, 1, 1, 1);
    RX_EN.configure(this, 1, 0, "RW", 1'b0, 1'b0, 1, 1, 1);
  endfunction
endclass

