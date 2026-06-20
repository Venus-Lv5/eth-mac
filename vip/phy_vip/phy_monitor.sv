class phy_monitor extends uvm_monitor;
  `uvm_component_utils(phy_monitor)

  virtual phy_if phy_vif;
  phy_config     cfg;

  phy_transaction tx_trans, rx_trans;

  uvm_analysis_port #(phy_transaction) phy_observe_port_tx;
  uvm_analysis_port #(phy_transaction) phy_observe_port_rx;

  function new(string name="phy_monitor", uvm_component parent);
    super.new(name, parent);
    phy_observe_port_tx = new("phy_observe_port_tx", this);
    phy_observe_port_rx = new("phy_observe_port_rx", this);
  endfunction: new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(virtual phy_if)::get(this, "", "phy_vif", phy_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get phy_if"))

    if (!uvm_config_db #(phy_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get phy_config"))
  endfunction: build_phase

  virtual task run_phase(uvm_phase phase);
    case (cfg.mode)
      phy_config::FULL:
        fork
          forever tx_capture();
          forever rx_capture();
        join

      phy_config::TX:
        forever tx_capture();

      phy_config::RX:
        forever rx_capture();
    endcase
  endtask: run_phase

  task tx_capture();
    bit [3:0] nibble_q[$];

    nibble_q.delete();

    do begin
      @(posedge phy_vif.TX_CLK);
      #1;
    end while (phy_vif.TX_EN != 1'b1);

    while (phy_vif.TX_EN == 1'b1) begin
      nibble_q.push_back(phy_vif.TXD);
      @(posedge phy_vif.TX_CLK);
      #1;
    end

    tx_trans = phy_transaction::type_id::create("tx_trans", this);
    decode_nibbles(nibble_q, tx_trans);

    `uvm_info("phy_monitor",
      $sformatf("Send tx_trans from monitor to scoreboard: \n%s", tx_trans.sprint()),
      UVM_LOW)

    phy_observe_port_tx.write(tx_trans);
  endtask: tx_capture

  task rx_capture();
    bit [3:0] nibble_q[$];

    nibble_q.delete();

    do begin
      @(posedge phy_vif.RX_CLK);
      #1;
    end while (phy_vif.RX_DV != 1'b1);

    while (phy_vif.RX_DV == 1'b1) begin
      nibble_q.push_back(phy_vif.RXD);
      @(posedge phy_vif.RX_CLK);
      #1;
    end

    rx_trans = phy_transaction::type_id::create("rx_trans", this);
    decode_nibbles(nibble_q, rx_trans);

    `uvm_info("phy_monitor",
      $sformatf("Send rx_trans from monitor to scoreboard: \n%s", rx_trans.sprint()),
      UVM_LOW)

    phy_observe_port_rx.write(rx_trans);
  endtask: rx_capture

  function void decode_nibbles(ref bit [3:0] nibble_q[$],
                               ref phy_transaction trans);
    bit [7:0] byte_q[$];
    int unsigned crc_idx;

    if (nibble_q.size() < 52) begin
      `uvm_error(get_type_name(),
        $sformatf("Captured frame is too short: nibble_count=%0d", nibble_q.size()))
      return;
    end

    if (nibble_q.size() % 2 != 0) begin
      `uvm_warning(get_type_name(),
        $sformatf("Captured odd nibble count: nibble_count=%0d", nibble_q.size()))
    end

    for (int i = 0; i + 1 < nibble_q.size(); i += 2) begin
      byte_q.push_back({nibble_q[i+1], nibble_q[i]});
    end

    trans.preamble = {
      byte_q[0],
      byte_q[1],
      byte_q[2],
      byte_q[3],
      byte_q[4],
      byte_q[5],
      byte_q[6]
    };

    trans.sfd = byte_q[7];

    trans.dst_mac = {
      byte_q[8],
      byte_q[9],
      byte_q[10],
      byte_q[11],
      byte_q[12],
      byte_q[13]
    };

    trans.src_mac = {
      byte_q[14],
      byte_q[15],
      byte_q[16],
      byte_q[17],
      byte_q[18],
      byte_q[19]
    };

    trans.type_len = {byte_q[20], byte_q[21]};

    if (trans.type_len == 16'h8808) begin
      trans.frame_type  = phy_transaction::CTRL_FRAME;
      trans.opcode      = {byte_q[22], byte_q[23]};
      trans.pause_timer = {byte_q[24], byte_q[25]};

      for (int i = 0; i < 42; i++) begin
        if ((26 + i) < (byte_q.size() - 4))
          trans.RSVD[i] = byte_q[26+i];
      end
    end
    else begin
      trans.frame_type = phy_transaction::ETH_FRAME;
      trans.payload.delete();

      for (int i = 22; i < byte_q.size() - 4; i++) begin
        trans.payload.push_back(byte_q[i]);
      end

      trans.len = trans.payload.size();
    end

    crc_idx = byte_q.size() - 4;
    trans.crc = {
      byte_q[crc_idx+3],
      byte_q[crc_idx+2],
      byte_q[crc_idx+1],
      byte_q[crc_idx+0]
    };
  endfunction: decode_nibbles

endclass: phy_monitor
