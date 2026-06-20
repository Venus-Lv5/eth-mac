class phy_driver extends uvm_driver #(phy_transaction);
  `uvm_component_utils(phy_driver)

  virtual phy_if  phy_vif;
  phy_config      cfg;

  function new(string name="phy_driver", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(virtual phy_if)::get(this, "", "phy_vif", phy_vif))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get vif from uvm_config_db. Please check!"))
    if(!uvm_config_db#(phy_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), $sformatf("Failed to get config from uvm_config_db. Please check!"))
  endfunction

  virtual task run_phase(uvm_phase phase);

    drive_idle();

    fork
      gen_tx_clk();
      gen_rx_clk();
      drive();
    join

  endtask

  task drive_idle();
    phy_vif.TX_CLK = 1'b0;
    phy_vif.RX_CLK = 1'b0;

    phy_vif.RXD    = 4'h0;
    phy_vif.RX_DV  = 1'b0;
    phy_vif.RX_ERR  = 1'b0;

    phy_vif.COL    = 1'b0;
    phy_vif.CRS    = 1'b0;
  endtask

  task gen_tx_clk();
    if (cfg.clk_en) begin
      forever begin
        #(cfg.clk_tp/2) phy_vif.TX_CLK = ~phy_vif.TX_CLK;
      end
    end
  endtask

  task gen_rx_clk();
    if (cfg.clk_en) begin
      forever begin
        #(cfg.clk_tp/2) phy_vif.RX_CLK = ~phy_vif.RX_CLK;
      end
    end
  endtask

  task drive();
    phy_transaction seq, rsp;
    `uvm_info("run_phase", "ENTERED...", UVM_HIGH)
		seq = phy_transaction::type_id::create("seq", this);

    forever begin
      seq_item_port.get_next_item(seq);
      case(seq.frame_type)
        phy_transaction::ETH_FRAME:  drive_rx_frame(seq);
        phy_transaction::CTRL_FRAME: drive_pause_frame(seq);
        phy_transaction::COLL_DET:   drive_coll(seq);
      endcase

      $cast(rsp, seq.clone());
      rsp.set_id_info(seq);
      `uvm_info("run_phase", $sformatf("Completed phy transaction:\n%s", rsp.sprint()), UVM_LOW)
      seq_item_port.item_done(rsp);
    end
  endtask: drive

  task drive_rx_frame(phy_transaction trans);
    bit [7:0] frame_bytes[$];
    bit [31:0] good_crc;

    trans.build_frame_bytes(frame_bytes, 1'b0);
    good_crc = trans.calc_crc32(frame_bytes);
    trans.crc = trans.bad_crc ? (good_crc ^ 32'h0000_0001) : good_crc;
    if (trans.bad_crc)
      `uvm_info("PHY_BAD_FCS",
        $sformatf("Injected bad FCS: good=0x%08h driven=0x%08h", good_crc, trans.crc),
        UVM_NONE)

    // Preamble
    for (int i = 6; i >= 0; i--) begin
      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.preamble[i*8 +: 4];
      phy_vif.RX_DV <= 1'b1;

      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.preamble[i*8+4 +: 4];
      phy_vif.RX_DV <= 1'b1;
    end

    //SFD
    @(posedge phy_vif.RX_CLK);
    phy_vif.RXD   <= trans.sfd[3:0];
    phy_vif.RX_DV <= 1'b1;

    @(posedge phy_vif.RX_CLK);
    phy_vif.RXD   <= trans.sfd[7:4];
    phy_vif.RX_DV <= 1'b1;

    // DA + SA + Type/Length + Payload + Pad
    foreach (frame_bytes[i]) begin
      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= frame_bytes[i][3:0];
      phy_vif.RX_DV <= 1'b1;

      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= frame_bytes[i][7:4];
      phy_vif.RX_DV <= 1'b1;
    end

    //FCS
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.crc[byte_idx*8 +: 4];
      phy_vif.RX_DV <= 1'b1;

      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.crc[byte_idx*8+4 +: 4];
      phy_vif.RX_DV <= 1'b1;
    end

    // End frame
    @(posedge phy_vif.RX_CLK);
    phy_vif.RXD    <= 4'h0;
    phy_vif.RX_DV  <= 1'b0;
    phy_vif.RX_ERR <= 1'b0;
  endtask: drive_rx_frame

  task drive_pause_frame(phy_transaction trans);
    bit [7:0] frame_bytes[$];
    bit [31:0] good_crc;

    trans.type_len = 16'h8808;
    trans.opcode   = 16'h0001;

    trans.build_frame_bytes(frame_bytes, 1'b1);
    good_crc = trans.calc_crc32(frame_bytes);
    trans.crc = trans.bad_crc ? (good_crc ^ 32'h0000_0001) : good_crc;
    if (trans.bad_crc)
      `uvm_info("PHY_BAD_FCS",
        $sformatf("Injected bad PAUSE FCS: good=0x%08h driven=0x%08h", good_crc, trans.crc),
        UVM_NONE)

    // Drive preamble
    for (int i = 6; i >= 0; i--) begin
      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.preamble[i*8 +: 4];
      phy_vif.RX_DV <= 1'b1;

      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.preamble[i*8+4 +: 4];
      phy_vif.RX_DV <= 1'b1;
    end

    // Drive SFD
    @(posedge phy_vif.RX_CLK);
    phy_vif.RXD   <= trans.sfd[3:0];
    phy_vif.RX_DV <= 1'b1;

    @(posedge phy_vif.RX_CLK);
    phy_vif.RXD   <= trans.sfd[7:4];
    phy_vif.RX_DV <= 1'b1;

    // Drive pause frame bytes
    foreach (frame_bytes[i]) begin
      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= frame_bytes[i][3:0];
      phy_vif.RX_DV <= 1'b1;

      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= frame_bytes[i][7:4];
      phy_vif.RX_DV <= 1'b1;
    end

    // Drive FCS
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.crc[byte_idx*8 +: 4];
      phy_vif.RX_DV <= 1'b1;

      @(posedge phy_vif.RX_CLK);
      phy_vif.RXD   <= trans.crc[byte_idx*8+4 +: 4];
      phy_vif.RX_DV <= 1'b1;
    end

    // End frame
    @(posedge phy_vif.RX_CLK);
    phy_vif.RXD    <= 4'h0;
    phy_vif.RX_DV  <= 1'b0;
    phy_vif.RX_ERR <= 1'b0;

  endtask: drive_pause_frame

  task drive_coll(phy_transaction trans);
    phy_vif.CRS <= 1'b0;

    wait (phy_vif.TX_EN === 1'b1);

    repeat (trans.coll_det_delay) begin
      @(posedge phy_vif.TX_CLK);
    end

    phy_vif.COL <= 1'b1;

    repeat (8) begin
      @(posedge phy_vif.TX_CLK);
    end

    phy_vif.COL <= 1'b0;
  endtask: drive_coll

endclass: phy_driver
