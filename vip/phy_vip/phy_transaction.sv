class phy_transaction extends uvm_sequence_item;

	typedef enum bit [1:0] {
		ETH_FRAME  = 0,
		COLL_DET   = 1,
		CTRL_FRAME = 2,
		rsvd       = 3
	} frame_type_enum;

	rand frame_type_enum    frame_type;

  rand  bit [55:0]        preamble;
  rand  bit [7:0]         sfd;
  rand  bit [7:0]         payload[$];
  rand  bit [15:0]        len;
  rand  bit [31:0]        crc;
  rand  bit               bad_crc;

  //Pause frame
  rand  bit [47:0]         dst_mac;
  rand  bit [47:0]         src_mac;
  rand  bit [15:0]         opcode;
  rand  bit [15:0]         pause_timer;
  rand  bit [7:0]          RSVD[41:0];
  rand  bit [15:0]         type_len;

  rand  int unsigned       coll_det_delay;

  constraint frame_c {
    soft frame_type == ETH_FRAME;
    soft preamble   == 56'h55_5555_5555_5555;
    soft sfd        == 8'hD5;
    soft len inside   {[0:1500]};
  }

  constraint payload_c {
    payload.size()  == len;
  }

  constraint bad_crc_c {
    soft bad_crc == 1'b0;
  }

	`uvm_object_utils_begin(phy_transaction)
    `uvm_field_enum      (frame_type_enum,  frame_type,        UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (preamble,    UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (sfd,         UVM_ALL_ON | UVM_HEX)
		`uvm_field_queue_int (payload,     UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (len,         UVM_ALL_ON | UVM_DEC)
		`uvm_field_int       (crc,         UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (bad_crc,     UVM_ALL_ON | UVM_BIN)
		`uvm_field_int       (dst_mac,     UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (src_mac,     UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (opcode,      UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (pause_timer, UVM_ALL_ON | UVM_HEX)
		`uvm_field_sarray_int(RSVD,        UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (type_len,    UVM_ALL_ON | UVM_HEX)
		`uvm_field_int       (coll_det_delay, UVM_ALL_ON | UVM_DEC)
	`uvm_object_utils_end

	function new(string name = "phy_transaction");
		super.new(name);

    dst_mac    = 48'hAA_AA_AA_AA_AA_AA;
    src_mac    = 48'h11_22_33_44_55_66;

    opcode     = 16'h0001;
    type_len   = 16'h8808;
    coll_det_delay = 0;
    bad_crc        = 1'b0;
	endfunction: new

	function void post_randomize();
    bit [7:0] frame_bytes[$];

    build_frame_bytes(frame_bytes, (frame_type == CTRL_FRAME));
    crc = calc_crc32(frame_bytes);
	endfunction: post_randomize

  function void build_frame_bytes(ref bit [7:0] frame_bytes[$], input bit is_pause);
    int unsigned pad_len;
    frame_bytes.delete();

    for (int i = 5; i >= 0; i--) begin
      frame_bytes.push_back(dst_mac[i*8 +: 8]);
    end

    for (int i = 5; i >= 0; i--) begin
      frame_bytes.push_back(src_mac[i*8 +: 8]);
    end

    if (is_pause) begin
      //Pause frame type
      frame_bytes.push_back(type_len[15:8]);
      frame_bytes.push_back(type_len[7:0]);

      // PAUSE opcode
      frame_bytes.push_back(opcode[15:8]);
      frame_bytes.push_back(opcode[7:0]);

      // PAUSE timer
      frame_bytes.push_back(pause_timer[15:8]);
      frame_bytes.push_back(pause_timer[7:0]);

      // Reserved / padding
      foreach (RSVD[i]) begin
        frame_bytes.push_back(RSVD[i]);
      end
    end
    else begin
      frame_bytes.push_back(len[15:8]);
      frame_bytes.push_back(len[7:0]);

      // Normal payload
      foreach (payload[i]) begin
        frame_bytes.push_back(payload[i]);
      end

      // Pad normal Ethernet frame to minimum payload size
      if (payload.size() < 46) begin
        pad_len = 46 - payload.size();

        repeat (pad_len) begin
          frame_bytes.push_back(8'h00);
        end
      end
    end
  endfunction: build_frame_bytes

  function bit [31:0] calc_crc32(input bit [7:0] data_bytes[$]);
    bit [31:0] crc_tmp;
    bit        mix;

    crc_tmp = 32'hFFFF_FFFF;

    foreach (data_bytes[i]) begin
      for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
        mix = crc_tmp[0] ^ data_bytes[i][bit_idx];
        crc_tmp = crc_tmp >> 1;

        if (mix) begin
          crc_tmp = crc_tmp ^ 32'hEDB8_8320;
        end
      end
    end

    return ~crc_tmp;
  endfunction: calc_crc32

endclass: phy_transaction
