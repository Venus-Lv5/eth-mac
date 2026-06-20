`uvm_analysis_imp_decl(_phy_tx)
`uvm_analysis_imp_decl(_phy_rx)
`uvm_analysis_imp_decl(_ahb)

class eth_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(eth_scoreboard)

  `include "eth_coverage.sv"

  localparam bit [47:0] PAUSE_DA          = 48'h01_80_C2_00_00_01;
  localparam bit [15:0] PAUSE_TYPE        = 16'h8808;
  localparam bit [15:0] PAUSE_OPCODE      = 16'h0001;
  localparam int unsigned MAX_NORMAL_LEN  = 1500;
  localparam int unsigned MIN_PAYLOAD_LEN = 46;

  uvm_analysis_imp_phy_tx #(phy_transaction, eth_scoreboard) phy_tx_export;
  uvm_analysis_imp_phy_rx #(phy_transaction, eth_scoreboard) phy_rx_export;
  uvm_analysis_imp_ahb    #(ahb_transaction, eth_scoreboard) ahb_export;

  phy_transaction phy_tx_queue[$];
  phy_transaction phy_rx_queue[$];

  bit [15:0] ahb_tx_len_queue[$];
  bit [31:0] ahb_tx_data_queue[$];
  bit [31:0] ahb_tx_cmd_queue[$];
  bit [15:0] ahb_rx_len_queue[$];
  bit [31:0] ahb_rx_data_queue[$];

  // IER/FSR/RSVD/PAUSE_CTRL are not checked by this scoreboard.

  phy_config cfg;

  bit [47:0] mac_sa;
  bit [47:0] tx_da;
  bit [31:0] mac_ctrl;
  bit [31:0] hash_l;
  bit [31:0] hash_h;

  bit [47:0] tx_exp_da_queue[$];
  bit [47:0] tx_exp_sa_queue[$];
  bit [15:0] tx_exp_len_queue[$];
  bit [7:0]  tx_exp_payload_queue[$][$];

  bit [15:0] rx_exp_len_queue[$];
  bit [7:0]  rx_exp_payload_queue[$][$];
  bit [15:0] rx_act_len_queue[$];
  bit [7:0]  rx_act_payload_queue[$][$];

  bit        rx_read_active;
  bit [15:0] rx_read_len;
  int unsigned rx_read_words_need;
  int unsigned rx_read_words_seen;
  bit [7:0] rx_read_payload[$];

  function new(string name="eth_scoreboard", uvm_component parent);
    super.new(name, parent);
    mac_ctrl = 32'h0000_0020;
    coverage_ier = 32'h0000_0000;
    ETH_CONFIG_COVERGROUP = new();
    ETH_FRAME_COVERGROUP = new();
    ETH_INTERRUPT_COVERGROUP = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(phy_config)::get(this, "", "phy_cfg", cfg))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get phy_config"))

    phy_tx_export = new("phy_tx_export", this);
    phy_rx_export = new("phy_rx_export", this);
    ahb_export    = new("ahb_export", this);

    ETH_CONFIG_COVERGROUP.sample(cfg.mode, cfg.freq,
                                 {cfg.pro, cfg.fil_en, cfg.bro});
  endfunction

  virtual task run_phase(uvm_phase phase);
  endtask

  virtual function void write_phy_tx(phy_transaction trans);
    `uvm_info("run_phase", $sformatf("Get frame data from tx: \n%s", trans.sprint()), UVM_LOW)
    sample_frame_coverage(COV_TXD, trans);
    phy_tx_queue.push_back(trans);
    compare();
  endfunction

  virtual function void write_phy_rx(phy_transaction trans);
    `uvm_info("run_phase", $sformatf("Get frame data from rx: \n%s", trans.sprint()), UVM_LOW)
    sample_frame_coverage(COV_RXD, trans);
    phy_rx_queue.push_back(trans);
    compare();
  endfunction

  virtual function void write_ahb(ahb_transaction trans);
    if (trans.xact_type == ahb_transaction::WRITE) begin
      case (trans.addr)
        10'h0C: coverage_ier       = trans.data;
        10'h00: mac_sa[31:0]     = trans.data;
        10'h04: mac_sa[47:32]    = trans.data[15:0];
        10'h10: mac_ctrl         = trans.data;
        10'h20: hash_l           = trans.data;
        10'h24: hash_h           = trans.data;
        10'h40: tx_da[31:0]      = trans.data;
        10'h44: tx_da[47:32]     = trans.data[15:0];
        10'h48: ahb_tx_len_queue.push_back(trans.data[15:0]);
        10'h4C: ahb_tx_data_queue.push_back(trans.data);
        10'h50: ahb_tx_cmd_queue.push_back(trans.data);
        default: ;
      endcase
    end
    else if (trans.xact_type == ahb_transaction::READ) begin
      case (trans.addr)
        10'h60: sample_interrupt_coverage(trans.data);
        10'h64: ahb_rx_len_queue.push_back(trans.data[15:0]);
        10'h68: ahb_rx_data_queue.push_back(trans.data);
        default: ;
      endcase
    end

    compare();
  endfunction

  function int unsigned word_count(input int unsigned byte_count);
    return (byte_count + 3) / 4;
  endfunction

  function void push_mac_bytes(input bit [47:0] mac,
                               ref bit [7:0] byte_q[$]);
    for (int i = 5; i >= 0; i--)
      byte_q.push_back(mac[i*8 +: 8]);
  endfunction

  function void push_word_bytes(input bit [31:0] word,
                                input int unsigned byte_cnt,
                                ref bit [7:0] payload[$]);
    if (byte_cnt > 0) payload.push_back(word[31:24]);
    if (byte_cnt > 1) payload.push_back(word[23:16]);
    if (byte_cnt > 2) payload.push_back(word[15:8]);
    if (byte_cnt > 3) payload.push_back(word[7:0]);
  endfunction

  function void build_normal_frame_bytes(input bit [47:0] da,
                                         input bit [47:0] sa,
                                         input bit [15:0] len,
                                         ref bit [7:0] payload[$],
                                         ref bit [7:0] frame_bytes[$]);
    frame_bytes.delete();

    push_mac_bytes(da, frame_bytes);
    push_mac_bytes(sa, frame_bytes);
    frame_bytes.push_back(len[15:8]);
    frame_bytes.push_back(len[7:0]);

    foreach (payload[i])
      frame_bytes.push_back(payload[i]);

    for (int i = payload.size(); i < MIN_PAYLOAD_LEN; i++)
      frame_bytes.push_back(8'h00);
  endfunction

  function void build_actual_frame_bytes(phy_transaction trans,
                                         ref bit [7:0] frame_bytes[$]);
    frame_bytes.delete();

    push_mac_bytes(trans.dst_mac, frame_bytes);
    push_mac_bytes(trans.src_mac, frame_bytes);
    frame_bytes.push_back(trans.type_len[15:8]);
    frame_bytes.push_back(trans.type_len[7:0]);

    if (trans.frame_type == phy_transaction::CTRL_FRAME) begin
      frame_bytes.push_back(trans.opcode[15:8]);
      frame_bytes.push_back(trans.opcode[7:0]);
      frame_bytes.push_back(trans.pause_timer[15:8]);
      frame_bytes.push_back(trans.pause_timer[7:0]);
      foreach (trans.RSVD[i])
        frame_bytes.push_back(trans.RSVD[i]);
    end
    else begin
      foreach (trans.payload[i])
        frame_bytes.push_back(trans.payload[i]);
    end
  endfunction

  function bit [31:0] calc_crc32(input bit [7:0] data_bytes[$]);
    bit [31:0] crc_tmp;
    bit        mix;

    crc_tmp = 32'hFFFF_FFFF;

    foreach (data_bytes[i]) begin
      for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
        mix = crc_tmp[0] ^ data_bytes[i][bit_idx];
        crc_tmp = crc_tmp >> 1;
        if (mix) crc_tmp = crc_tmp ^ 32'hEDB8_8320;
      end
    end

    return ~crc_tmp;
  endfunction

  function bit [31:0] calc_hash_crc_nibble(input bit [47:0] da);
    bit [31:0] crc_tmp;
    bit [3:0]  nibble;

    crc_tmp = 32'hFFFF_FFFF;

    for (int i = 5; i >= 0; i--) begin
      for (int n = 0; n < 2; n++) begin
        nibble = (n == 0) ? da[i*8 +: 4] : da[i*8 + 4 +: 4];
        crc_tmp = next_hash_crc_nibble(crc_tmp,
                                       {nibble[0], nibble[1],
                                        nibble[2], nibble[3]});
      end
    end

    return crc_tmp;
  endfunction

  function bit [31:0] next_hash_crc_nibble(input bit [31:0] crc,
                                           input bit [3:0] data);
    bit [31:0] next_crc;

    next_crc[0]  = data[0] ^ crc[28];
    next_crc[1]  = data[1] ^ data[0] ^ crc[28] ^ crc[29];
    next_crc[2]  = data[2] ^ data[1] ^ data[0] ^ crc[28] ^ crc[29] ^ crc[30];
    next_crc[3]  = data[3] ^ data[2] ^ data[1] ^ crc[29] ^ crc[30] ^ crc[31];
    next_crc[4]  = data[3] ^ data[2] ^ data[0] ^ crc[28] ^ crc[30] ^ crc[31] ^ crc[0];
    next_crc[5]  = data[3] ^ data[1] ^ data[0] ^ crc[28] ^ crc[29] ^ crc[31] ^ crc[1];
    next_crc[6]  = data[2] ^ data[1] ^ crc[29] ^ crc[30] ^ crc[2];
    next_crc[7]  = data[3] ^ data[2] ^ data[0] ^ crc[28] ^ crc[30] ^ crc[31] ^ crc[3];
    next_crc[8]  = data[3] ^ data[1] ^ data[0] ^ crc[28] ^ crc[29] ^ crc[31] ^ crc[4];
    next_crc[9]  = data[2] ^ data[1] ^ crc[29] ^ crc[30] ^ crc[5];
    next_crc[10] = data[3] ^ data[2] ^ data[0] ^ crc[28] ^ crc[30] ^ crc[31] ^ crc[6];
    next_crc[11] = data[3] ^ data[1] ^ data[0] ^ crc[28] ^ crc[29] ^ crc[31] ^ crc[7];
    next_crc[12] = data[2] ^ data[1] ^ data[0] ^ crc[28] ^ crc[29] ^ crc[30] ^ crc[8];
    next_crc[13] = data[3] ^ data[2] ^ data[1] ^ crc[29] ^ crc[30] ^ crc[31] ^ crc[9];
    next_crc[14] = data[3] ^ data[2] ^ crc[30] ^ crc[31] ^ crc[10];
    next_crc[15] = data[3] ^ crc[31] ^ crc[11];
    next_crc[16] = data[0] ^ crc[28] ^ crc[12];
    next_crc[17] = data[1] ^ crc[29] ^ crc[13];
    next_crc[18] = data[2] ^ crc[30] ^ crc[14];
    next_crc[19] = data[3] ^ crc[31] ^ crc[15];
    next_crc[20] = crc[16];
    next_crc[21] = crc[17];
    next_crc[22] = data[0] ^ crc[28] ^ crc[18];
    next_crc[23] = data[1] ^ data[0] ^ crc[29] ^ crc[28] ^ crc[19];
    next_crc[24] = data[2] ^ data[1] ^ crc[30] ^ crc[29] ^ crc[20];
    next_crc[25] = data[3] ^ data[2] ^ crc[31] ^ crc[30] ^ crc[21];
    next_crc[26] = data[3] ^ data[0] ^ crc[31] ^ crc[28] ^ crc[22];
    next_crc[27] = data[1] ^ crc[29] ^ crc[23];
    next_crc[28] = data[2] ^ crc[30] ^ crc[24];
    next_crc[29] = data[3] ^ crc[31] ^ crc[25];
    next_crc[30] = crc[26];
    next_crc[31] = crc[27];

    return next_crc;
  endfunction

  function bit check_expected_fcs(string tag,
                                  input bit [47:0] da,
                                  input bit [47:0] sa,
                                  input bit [15:0] len,
                                  ref bit [7:0] payload[$],
                                  input bit [31:0] got_crc);
    bit [7:0] frame_bytes[$];
    bit [31:0] exp_crc;

    build_normal_frame_bytes(da, sa, len, payload, frame_bytes);
    exp_crc = calc_crc32(frame_bytes);

    if (got_crc !== exp_crc) begin
      `uvm_error(get_type_name(),
        $sformatf("%s FCS mismatch: expected=0x%08h got=0x%08h",
                  tag, exp_crc, got_crc))
      return 1'b0;
    end

    return 1'b1;
  endfunction

  function bit check_actual_fcs(string tag, phy_transaction trans);
    bit [7:0] frame_bytes[$];
    bit [31:0] exp_crc;

    build_actual_frame_bytes(trans, frame_bytes);
    exp_crc = calc_crc32(frame_bytes);

    if (trans.crc !== exp_crc) begin
      `uvm_error(get_type_name(),
        $sformatf("%s FCS mismatch: expected=0x%08h got=0x%08h",
                  tag, exp_crc, trans.crc))
      return 1'b0;
    end

    return 1'b1;
  endfunction

  function bit multicast_hash_match(input bit [47:0] da);
    bit [31:0] crc_raw;
    bit [5:0]  hash_idx;
    bit [31:0] hash_reg;
    bit [7:0]  hash_byte;

    crc_raw  = calc_hash_crc_nibble(da);
    hash_idx = crc_raw[31:26];
    hash_reg = hash_idx[5] ? hash_h : hash_l;

    case (hash_idx[4:3])
      2'b00: hash_byte = hash_reg[7:0];
      2'b01: hash_byte = hash_reg[15:8];
      2'b10: hash_byte = hash_reg[23:16];
      default: hash_byte = hash_reg[31:24];
    endcase

    return hash_byte[hash_idx[2:0]];
  endfunction

  function void check_RX_addr_config(phy_transaction trans);
    bit is_broadcast;
    bit is_multicast;
    bit is_unicast_match;
    bit hash_ok;
    bit addr_ok;

    is_broadcast     = (trans.dst_mac == 48'hFF_FF_FF_FF_FF_FF);
    is_multicast     = trans.dst_mac[40] & !is_broadcast;
    is_unicast_match = (trans.dst_mac == mac_sa);
    hash_ok          = is_multicast ? multicast_hash_match(trans.dst_mac) : 1'b0;
    addr_ok          = mac_ctrl[4] || is_unicast_match ||
                       (is_broadcast && mac_ctrl[2]) ||
                       (is_multicast && mac_ctrl[3] && hash_ok);

    `uvm_info(get_type_name(),
      $sformatf("RX address detect: DA=%012h SA=%012h MAC_SA=%012h peer=%012h unicast_match=%0b broadcast=%0b multicast=%0b hash_match=%0b BRO=%0b FIL_EN=%0b PRO=%0b RX_EN=%0b",
                trans.dst_mac, trans.src_mac, mac_sa, tx_da,
                is_unicast_match, is_broadcast, is_multicast, hash_ok,
                mac_ctrl[2], mac_ctrl[3], mac_ctrl[4], mac_ctrl[0]),
      UVM_LOW)

    if (!addr_ok) begin
      `uvm_error(get_type_name(),
        $sformatf("RX DA config mismatch: DA=%012h MAC_SA=%012h BRO=%0b FIL_EN=%0b PRO=%0b multicast=%0b hash_match=%0b",
                  trans.dst_mac, mac_sa, mac_ctrl[2], mac_ctrl[3],
                  mac_ctrl[4], is_multicast, hash_ok))
    end

    if ((tx_da != 48'h0) && (trans.src_mac !== tx_da)) begin
      `uvm_error(get_type_name(),
        $sformatf("RX SA config mismatch: expected peer/TX_DA=%012h got RXD SA=%012h",
                  tx_da, trans.src_mac))
    end
  endfunction

  function bit check_pause_frame(string tag,
                                 phy_transaction trans,
                                 input bit check_src_mac);
    bit ok;

    ok = 1'b1;

    if (trans.dst_mac !== PAUSE_DA) begin
      `uvm_error(get_type_name(),
        $sformatf("%s PAUSE DA mismatch: expected=%012h got=%012h",
                  tag, PAUSE_DA, trans.dst_mac))
      ok = 1'b0;
    end

    if (check_src_mac && (trans.src_mac !== mac_sa)) begin
      `uvm_error(get_type_name(),
        $sformatf("%s PAUSE SA mismatch: expected MAC_SA=%012h got=%012h",
                  tag, mac_sa, trans.src_mac))
      ok = 1'b0;
    end

    if (trans.type_len !== PAUSE_TYPE) begin
      `uvm_error(get_type_name(),
        $sformatf("%s PAUSE type mismatch: expected=0x%04h got=0x%04h",
                  tag, PAUSE_TYPE, trans.type_len))
      ok = 1'b0;
    end

    if (trans.opcode !== PAUSE_OPCODE) begin
      `uvm_error(get_type_name(),
        $sformatf("%s PAUSE opcode mismatch: expected=0x%04h got=0x%04h",
                  tag, PAUSE_OPCODE, trans.opcode))
      ok = 1'b0;
    end

    if (!check_actual_fcs(tag, trans))
      ok = 1'b0;

    `uvm_info(get_type_name(),
      $sformatf("%s PAUSE frame detected: timer=0x%04h", tag, trans.pause_timer),
      UVM_LOW)

    return ok;
  endfunction

  function bit compare_payload(string tag,
                               ref bit [7:0] exp_payload[$],
                               ref bit [7:0] act_payload[$]);
    bit ok;

    ok = 1'b1;

    if (act_payload.size() != exp_payload.size()) begin
      `uvm_error(get_type_name(),
        $sformatf("%s payload size mismatch: expected=%0d got=%0d",
                  tag, exp_payload.size(), act_payload.size()))
      ok = 1'b0;
    end

    for (int i = 0; i < exp_payload.size() && i < act_payload.size(); i++) begin
      if (act_payload[i] !== exp_payload[i]) begin
        `uvm_error(get_type_name(),
          $sformatf("%s payload[%0d] mismatch: expected=0x%02h got=0x%02h",
                    tag, i, exp_payload[i], act_payload[i]))
        ok = 1'b0;
      end
    end

    return ok;
  endfunction

  function void collect_TX_expected();
    bit [15:0] exp_len;
    bit [7:0]  exp_payload[$];
    int unsigned num_words;
    int unsigned remain_bytes;
    int unsigned byte_cnt;

    while (ahb_tx_cmd_queue.size() > 0) begin
      if (ahb_tx_cmd_queue[0][0] == 1'b0) begin
        void'(ahb_tx_cmd_queue.pop_front());
        continue;
      end

      if (ahb_tx_len_queue.size() == 0)
        return;

      exp_len = ahb_tx_len_queue[0];

      if (exp_len > MAX_NORMAL_LEN) begin
        void'(ahb_tx_cmd_queue.pop_front());
        void'(ahb_tx_len_queue.pop_front());
        `uvm_info(get_type_name(),
          $sformatf("Skip TX expected frame because TX_LEN is invalid: %0d", exp_len),
          UVM_LOW)
        continue;
      end

      num_words = word_count(exp_len);
      if (ahb_tx_data_queue.size() < num_words)
        return;

      void'(ahb_tx_cmd_queue.pop_front());
      void'(ahb_tx_len_queue.pop_front());

      exp_payload.delete();
      remain_bytes = exp_len;

      for (int i = 0; i < num_words; i++) begin
        byte_cnt = (remain_bytes >= 4) ? 4 : remain_bytes;
        push_word_bytes(ahb_tx_data_queue.pop_front(), byte_cnt, exp_payload);
        remain_bytes -= byte_cnt;
      end

      tx_exp_da_queue.push_back(tx_da);
      tx_exp_sa_queue.push_back(mac_sa);
      tx_exp_len_queue.push_back(exp_len);
      tx_exp_payload_queue.push_back(exp_payload);

      `uvm_info(get_type_name(),
        $sformatf("Build TX expected frame DA=%012h SA=%012h LEN=%0d payload_bytes=%0d",
                  tx_da, mac_sa, exp_len, exp_payload.size()),
        UVM_LOW)
    end
  endfunction

  function void check_TX_data();
    phy_transaction trans;
    bit [47:0] exp_da;
    bit [47:0] exp_sa;
    bit [15:0] exp_len;
    bit [7:0]  exp_payload[$];
    bit [7:0]  act_payload[$];
    int unsigned exp_wire_payload_size;
    bit ok;

    collect_TX_expected();

    while (phy_tx_queue.size() > 0) begin
      trans = phy_tx_queue[0];

      if (trans.frame_type == phy_transaction::CTRL_FRAME) begin
        trans = phy_tx_queue.pop_front();
        void'(check_pause_frame("TXD", trans, 1'b1));
        continue;
      end

      if (trans.frame_type != phy_transaction::ETH_FRAME) begin
        void'(phy_tx_queue.pop_front());
        `uvm_info(get_type_name(), "TXD frame skipped because it is not ETH_FRAME", UVM_LOW)
        continue;
      end

      if (tx_exp_len_queue.size() == 0)
        return;

      exp_da      = tx_exp_da_queue.pop_front();
      exp_sa      = tx_exp_sa_queue.pop_front();
      exp_len     = tx_exp_len_queue.pop_front();
      exp_payload = tx_exp_payload_queue.pop_front();
      trans       = phy_tx_queue.pop_front();
      ok          = 1'b1;

      `uvm_info(get_type_name(), "Entered check_TX_data", UVM_LOW)

      if (trans.dst_mac !== exp_da) begin
        `uvm_error(get_type_name(),
          $sformatf("TX DA mismatch: expected=%012h got=%012h",
                    exp_da, trans.dst_mac))
        ok = 1'b0;
      end

      if (trans.src_mac !== exp_sa) begin
        `uvm_error(get_type_name(),
          $sformatf("TX SA mismatch: expected=%012h got=%012h",
                    exp_sa, trans.src_mac))
        ok = 1'b0;
      end

      if (trans.type_len !== exp_len) begin
        `uvm_error(get_type_name(),
          $sformatf("TX LEN mismatch: expected=%0d got=%0d",
                    exp_len, trans.type_len))
        ok = 1'b0;
      end

      exp_wire_payload_size = (exp_payload.size() < MIN_PAYLOAD_LEN) ?
                              MIN_PAYLOAD_LEN : exp_payload.size();

      if (trans.payload.size() != exp_wire_payload_size) begin
        `uvm_error(get_type_name(),
          $sformatf("TX wire payload size mismatch: expected=%0d got=%0d",
                    exp_wire_payload_size, trans.payload.size()))
        ok = 1'b0;
      end

      act_payload.delete();
      for (int i = 0; i < exp_payload.size() && i < trans.payload.size(); i++)
        act_payload.push_back(trans.payload[i]);

      if (!compare_payload("TX", exp_payload, act_payload))
        ok = 1'b0;

      for (int i = exp_payload.size(); i < trans.payload.size(); i++) begin
        if (trans.payload[i] !== 8'h00) begin
          `uvm_error(get_type_name(),
            $sformatf("TX padding[%0d] mismatch: expected=0x00 got=0x%02h",
                      i, trans.payload[i]))
          ok = 1'b0;
        end
      end

      if (!check_expected_fcs("TXD", exp_da, exp_sa, exp_len,
                              exp_payload, trans.crc))
        ok = 1'b0;

      if (ok)
        `uvm_info(get_type_name(), "Exiting check_TX_data: TX matched", UVM_LOW)
      else
        `uvm_info(get_type_name(), "Exiting check_TX_data: TX mismatch", UVM_LOW)
    end
  endfunction

  function void collect_RX_expected();
    phy_transaction trans;
    bit [15:0] exp_len;
    bit [7:0]  exp_payload[$];

    while (phy_rx_queue.size() > 0) begin
      trans = phy_rx_queue.pop_front();
      exp_payload.delete();

      if (trans.frame_type == phy_transaction::CTRL_FRAME) begin
        void'(check_pause_frame("RXD", trans, 1'b0));
        continue;
      end

      if (trans.frame_type != phy_transaction::ETH_FRAME) begin
        `uvm_info(get_type_name(), "RXD frame skipped because it is not ETH_FRAME", UVM_LOW)
        continue;
      end

      check_RX_addr_config(trans);
      void'(check_actual_fcs("RXD", trans));

      exp_len = trans.type_len;

      if (trans.payload.size() < exp_len) begin
        `uvm_error(get_type_name(),
          $sformatf("RXD length mismatch: type_len=%0d but captured payload/pad bytes=%0d",
                    exp_len, trans.payload.size()))
        continue;
      end

      for (int i = 0; i < exp_len; i++)
        exp_payload.push_back(trans.payload[i]);

      rx_exp_len_queue.push_back(exp_len);
      rx_exp_payload_queue.push_back(exp_payload);

      `uvm_info(get_type_name(),
        $sformatf("Build RX expected frame LEN=%0d payload_bytes=%0d",
                  exp_len, exp_payload.size()),
        UVM_LOW)
    end
  endfunction

  function void collect_RX_reads();
    int unsigned remain_bytes;
    int unsigned byte_cnt;

    while (ahb_rx_len_queue.size() > 0) begin
      if (rx_read_active) begin
        `uvm_error(get_type_name(), "RX_LEN read while previous RX_DATA read is not complete")
        rx_read_payload.delete();
      end

      rx_read_active     = 1'b1;
      rx_read_len        = ahb_rx_len_queue.pop_front();
      rx_read_words_need = word_count(rx_read_len);
      rx_read_words_seen = 0;
      rx_read_payload.delete();

      if (rx_read_words_need == 0) begin
        if (rx_exp_len_queue.size() == 0) begin
          `uvm_info(get_type_name(), "RX_LEN read returns 0 while no RX expected frame is pending", UVM_LOW)
          rx_read_active = 1'b0;
          continue;
        end

        rx_act_len_queue.push_back(rx_read_len);
        rx_act_payload_queue.push_back(rx_read_payload);
        rx_read_active = 1'b0;
      end
    end

    while (rx_read_active && ahb_rx_data_queue.size() > 0 &&
           rx_read_words_seen < rx_read_words_need) begin
      remain_bytes = (rx_read_len > rx_read_payload.size()) ?
                     (rx_read_len - rx_read_payload.size()) : 0;
      byte_cnt = (remain_bytes >= 4) ? 4 : remain_bytes;
      push_word_bytes(ahb_rx_data_queue.pop_front(), byte_cnt, rx_read_payload);
      rx_read_words_seen++;
    end

    if (rx_read_active && rx_read_words_seen == rx_read_words_need) begin
      rx_act_len_queue.push_back(rx_read_len);
      rx_act_payload_queue.push_back(rx_read_payload);
      rx_read_active = 1'b0;
      rx_read_payload.delete();
    end
  endfunction

  function void compare_RX_queues();
    bit [15:0] exp_len;
    bit [15:0] act_len;
    bit [7:0]  exp_payload[$];
    bit [7:0]  act_payload[$];
    bit ok;

    while (rx_exp_len_queue.size() > 0 && rx_act_len_queue.size() > 0) begin
      exp_len     = rx_exp_len_queue.pop_front();
      exp_payload = rx_exp_payload_queue.pop_front();
      act_len     = rx_act_len_queue.pop_front();
      act_payload = rx_act_payload_queue.pop_front();
      ok          = 1'b1;

      `uvm_info(get_type_name(), "Entered check_RX_data", UVM_LOW)

      if (act_len !== exp_len) begin
        `uvm_error(get_type_name(),
          $sformatf("RX_LEN mismatch: expected=%0d got=%0d", exp_len, act_len))
        ok = 1'b0;
      end

      if (!compare_payload("RX", exp_payload, act_payload))
        ok = 1'b0;

      if (ok)
        `uvm_info(get_type_name(), "Exiting check_RX_data: RX matched", UVM_LOW)
      else
        `uvm_info(get_type_name(), "Exiting check_RX_data: RX mismatch", UVM_LOW)
    end
  endfunction

  function void check_RX_data();
    collect_RX_expected();
    collect_RX_reads();
    compare_RX_queues();
  endfunction

  function void compare();
    case (cfg.mode)
      phy_config::TX: begin
        check_TX_data();
      end
      phy_config::RX: begin
        check_RX_data();
      end
      phy_config::FULL: begin
        check_TX_data();
        check_RX_data();
      end
    endcase
  endfunction

endclass: eth_scoreboard
