class eth_RX_CMD_reg extends uvm_reg;
  `uvm_object_utils(eth_RX_CMD_reg)

  uvm_reg_field rsvd;
  rand uvm_reg_field RX_RELEASE;
  
  function new(string name="eth_RX_CMD_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rsvd = uvm_reg_field::type_id::create("rsvd");
    RX_RELEASE = uvm_reg_field::type_id::create("RX_RELEASE");

    rsvd.configure(this, 31, 1, "WO", 1'b0, 31'h00000000, 0, 1, 1);
    RX_RELEASE.configure(this, 1, 0, "WO", 1'b0, 1'b0, 0, 1, 1);
  endfunction
endclass

