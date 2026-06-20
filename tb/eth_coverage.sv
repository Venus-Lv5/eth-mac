  typedef enum bit {
    COV_TXD = 1'b0,
    COV_RXD = 1'b1
  } eth_cov_direction_e;

  typedef enum bit [2:0] {
    COV_INT_TX_DONE       = 3'd0,
    COV_INT_TX_ERR        = 3'd1,
    COV_INT_RX_AVAIL      = 3'd2,
    COV_INT_RX_BUSY       = 3'd3,
    COV_INT_RX_ERR        = 3'd4,
    COV_INT_RX_PAUSE_SEEN = 3'd5
  } eth_cov_interrupt_e;

  bit [31:0] coverage_ier;

  covergroup ETH_CONFIG_COVERGROUP with function sample(
    phy_config::mode_enum mode,
    phy_config::freq_enum freq,
    bit [2:0] filter_mode
  );
    option.per_instance = 1;

    mode_cp : coverpoint mode {
      bins full_duplex = {phy_config::FULL};
      // TX/RX-only modes are outside the current full-duplex regression.
      ignore_bins non_full_duplex = {phy_config::TX, phy_config::RX};
    }

    speed_cp : coverpoint freq {
      bins mii_100m = {phy_config::MII_100M};
      bins mii_10m  = {phy_config::MII_10M};
    }

    filter_cp : coverpoint filter_mode {
      bins unicast    = {3'b000};
      bins broadcast  = {3'b001};
      bins multicast  = {3'b010};
      bins promiscuous = {3'b100};
      ignore_bins unused_combinations = {3'b011, 3'b101, 3'b110, 3'b111};
    }

    speed_filter_cross : cross speed_cp, filter_cp;
  endgroup

  covergroup ETH_FRAME_COVERGROUP with function sample(
    eth_cov_direction_e direction,
    phy_transaction::frame_type_enum frame_type,
    phy_config::freq_enum freq,
    bit fcs_good,
    bit [15:0] pause_timer
  );
    option.per_instance = 1;

    direction_cp : coverpoint direction {
      bins txd = {COV_TXD};
      bins rxd = {COV_RXD};
    }

    frame_type_cp : coverpoint frame_type {
      bins ethernet = {phy_transaction::ETH_FRAME};
      bins pause    = {phy_transaction::CTRL_FRAME};
      // Collision injection is not part of the current full-duplex tests.
      ignore_bins collision = {phy_transaction::COLL_DET};
      ignore_bins reserved  = {phy_transaction::rsvd};
    }

    speed_cp : coverpoint freq {
      bins mii_100m = {phy_config::MII_100M};
      bins mii_10m  = {phy_config::MII_10M};
    }

    rx_fcs_cp : coverpoint fcs_good
      iff (direction == COV_RXD && frame_type == phy_transaction::ETH_FRAME) {
      bins good = {1'b1};
      bins bad  = {1'b0};
    }

    pause_timer_cp : coverpoint pause_timer
      iff (frame_type == phy_transaction::CTRL_FRAME) {
      bins zero    = {16'h0000};
      bins nonzero = {[16'h0001:16'hFFFE]};
      bins maximum = {16'hFFFF};
    }

    direction_type_speed_cross : cross direction_cp, frame_type_cp, speed_cp;
    fcs_speed_cross            : cross rx_fcs_cp, speed_cp;
  endgroup

  covergroup ETH_INTERRUPT_COVERGROUP with function sample(
    eth_cov_interrupt_e interrupt_source,
    phy_config::freq_enum freq
  );
    option.per_instance = 1;

    source_cp : coverpoint interrupt_source {
      bins tx_done       = {COV_INT_TX_DONE};
      bins tx_err        = {COV_INT_TX_ERR};
      bins rx_avail      = {COV_INT_RX_AVAIL};
      bins rx_busy       = {COV_INT_RX_BUSY};
      bins rx_err        = {COV_INT_RX_ERR};
      bins rx_pause_seen = {COV_INT_RX_PAUSE_SEEN};
    }

    speed_cp : coverpoint freq {
      bins mii_100m = {phy_config::MII_100M};
      bins mii_10m  = {phy_config::MII_10M};
    }

    source_speed_cross : cross source_cp, speed_cp;
  endgroup

  function void sample_frame_coverage(
    eth_cov_direction_e direction,
    phy_transaction trans
  );
    bit [7:0] frame_bytes[$];
    bit [31:0] expected_fcs;
    bit fcs_good;

    fcs_good = 1'b1;
    if (trans.frame_type inside {phy_transaction::ETH_FRAME,
                                 phy_transaction::CTRL_FRAME}) begin
      build_actual_frame_bytes(trans, frame_bytes);
      expected_fcs = calc_crc32(frame_bytes);
      fcs_good = (trans.crc === expected_fcs);
    end

    ETH_FRAME_COVERGROUP.sample(direction, trans.frame_type, cfg.freq,
                               fcs_good, trans.pause_timer);
  endfunction

  function void sample_interrupt_coverage(bit [31:0] fsr_data);
    if (coverage_ier[0] && fsr_data[2])
      ETH_INTERRUPT_COVERGROUP.sample(COV_INT_TX_DONE, cfg.freq);
    if (coverage_ier[1] && fsr_data[3])
      ETH_INTERRUPT_COVERGROUP.sample(COV_INT_TX_ERR, cfg.freq);
    if (coverage_ier[2] && fsr_data[4])
      ETH_INTERRUPT_COVERGROUP.sample(COV_INT_RX_AVAIL, cfg.freq);
    if (coverage_ier[3] && fsr_data[5])
      ETH_INTERRUPT_COVERGROUP.sample(COV_INT_RX_BUSY, cfg.freq);
    if (coverage_ier[4] && fsr_data[6])
      ETH_INTERRUPT_COVERGROUP.sample(COV_INT_RX_ERR, cfg.freq);
    if (coverage_ier[5] && fsr_data[9])
      ETH_INTERRUPT_COVERGROUP.sample(COV_INT_RX_PAUSE_SEEN, cfg.freq);
  endfunction
