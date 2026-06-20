class phy_col_delay_seq extends uvm_sequence #(phy_transaction);
  `uvm_object_utils(phy_col_delay_seq)

  rand int unsigned coll_det_delay;

  constraint coll_det_c {
    soft coll_det_delay == 0;
  }

  function new(string name = "phy_col_delay_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = phy_transaction::type_id::create("req");

    start_item(req);
    if (req.randomize() with {
      frame_type     == phy_transaction::COLL_DET;
      coll_det_delay == this.coll_det_delay;
      bad_crc        == 1'b0;
    })
      `uvm_info(get_type_name(), $sformatf("Send req to driver: \n%s", req.sprint()), UVM_LOW)
    else
      `uvm_fatal(get_type_name(), $sformatf("Randomize failed"))

    finish_item(req);
    get_response(rsp);
  endtask: body

endclass: phy_col_delay_seq
