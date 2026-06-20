class phy_pause_frame_seq extends uvm_sequence #(phy_transaction);
  `uvm_object_utils(phy_pause_frame_seq)

  rand bit [15:0] pause_timer;
  rand bit [47:0] dst_mac;
  rand bit [47:0] src_mac;

  constraint pause_frame_c {
    soft pause_timer == 16'h0001;
    soft dst_mac     == 48'h01_80_c2_00_00_01;
    soft src_mac     == 48'h11_22_33_44_55_66;
  }

  function new(string name = "phy_pause_frame_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = phy_transaction::type_id::create("req");

    start_item(req);
    if (req.randomize() with {
      frame_type  == phy_transaction::CTRL_FRAME;
      type_len    == 16'h8808;
      opcode      == 16'h0001;
      pause_timer == local::pause_timer;
      dst_mac     == local::dst_mac;
      src_mac     == local::src_mac;
      bad_crc     == 1'b0;
      foreach (RSVD[i]) RSVD[i] == 8'h00;
    })
      `uvm_info(get_type_name(), $sformatf("Send req to driver: \n%s", req.sprint()), UVM_LOW)
    else
      `uvm_fatal(get_type_name(), $sformatf("Randomize failed"))

    finish_item(req);
    get_response(rsp);
  endtask: body

endclass: phy_pause_frame_seq
