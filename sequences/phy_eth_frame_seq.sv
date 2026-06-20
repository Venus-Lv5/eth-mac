class phy_eth_frame_seq extends uvm_sequence #(phy_transaction);
  `uvm_object_utils(phy_eth_frame_seq);

  rand int unsigned len;
  rand bit [47:0]  dst_mac;
  rand bit [47:0]  src_mac;

  constraint len_c {
    soft len inside {[46:1500]};
  }


  function new(string name = "phy_eth_frame_seq");
    super.new(name);
    len     = 46;
    dst_mac = 48'h01_80_c2_00_00_01;
    src_mac = 48'h11_22_33_44_55_66;
  endfunction

  virtual task body();
    req = phy_transaction::type_id::create("req");

    start_item(req);
	    if (req.randomize() with {
	      frame_type == phy_transaction::ETH_FRAME;
	      len        == local::len;
	      dst_mac    == local::dst_mac;
	      src_mac    == local::src_mac;
	      bad_crc    == 1'b0;
	    })
      `uvm_info(get_type_name(), $sformatf("Send req to driver: \n%s", req.sprint()), UVM_LOW)
    else
      `uvm_fatal(get_type_name(), $sformatf("Randomize failed"))

    finish_item(req);
    get_response(rsp);
  endtask: body

endclass: phy_eth_frame_seq
