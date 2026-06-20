class full_10M_rx_pause_test extends eth_base_test;
  `uvm_component_utils(full_10M_rx_pause_test)

  function new(string name="full_10M_rx_pause_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		assert(cfg.randomize() with {
			mode      == phy_config::FULL;
      freq      == phy_config::MII_10M;
      mac_addr 	== 48'h11_22_33_44_55_66;
      phy_addr 	== 48'hAA_BB_CC_DD_EE_FF;
      hash			== 0;
      pro				== 0;
      fil_en		== 0;
      bro				== 0;
      tx_len    >  128;
		})
		else `uvm_fatal(get_type_name(), $sformatf("Failed to random uart_config"))

    config_mac(cfg);
	endfunction

  task send_tx(ref uvm_status_e status, ref bit [31:0] wdata_q[$]);
    regmodel.TX_LEN.write(status, config_tx_len());

    wdata_q.delete();
    random_payload(cfg.tx_len, wdata_q);

    for (int i = 0; i < (cfg.tx_len+3)/4; i++) begin
      regmodel.TX_DATA.write(status, wdata_q[i]);
    end

    regmodel.TX_CMD.write(status, 32'h0000_0001);
  endtask

	virtual task run_phase(uvm_phase phase);
    localparam bit [15:0] PAUSE_TIMER = 16'h0020;
    localparam int unsigned PAUSE_QUANTA_TX_CLK = 128;
    localparam time PAUSE_QUANTA_TIME = 51200;
    localparam int unsigned PAUSE_TOL_QUANTA = 0;
    localparam int unsigned IFG_TX_CLK = 24;
    localparam int unsigned IFG_TOL_TX_CLK = 64;
    localparam int unsigned WAIT_TX_CLK = 20000;

    uvm_status_e status;

    bit [31:0] wdata_q[$];
    bit got_pause_irq;
    bit tx_cycle_run;
    bit seen0;
    bit seen1;
    bit seen2;
    bit seen_pause_timer;
    bit [15:0] pause_timer_capture;

    int unsigned tx_cycle;
    int unsigned time0;
    int unsigned time1;
    int unsigned time2;
    int unsigned gap1;
    int unsigned gap2;
    int unsigned pause_time;
    int unsigned frame_pause_time;
    int unsigned exp_pause_time;
    int signed delta;
    int unsigned abs_delta;
    time time0_t;
    time time2_t;
    time pause_time_t;

    phase.raise_objection(this);

    tx_cycle = 0;
    tx_cycle_run = 1;
    fork
      begin
        while (tx_cycle_run) begin
          @(posedge phy_vif.TX_CLK);
          tx_cycle++;
        end
      end
    join_none

    wdata_q.delete();
    wdata_q.push_back(config_mac_addr_l());
    wdata_q.push_back(config_mac_addr_h());
    wdata_q.push_back(32'h0000_0003);                 //PAUSE control
    wdata_q.push_back(32'h0000_0020);                 //IER: RX_PAUSE_SEEN
    wdata_q.push_back(config_mac_ctrl());
    burst_write_reg_range(10'h00, 10'h10, wdata_q, 1);

    wdata_q.delete();
    wdata_q.push_back(31'h0);
    wdata_q.push_back(31'h0);
    burst_write_reg_range(10'h20, 10'h24, wdata_q, 1);

    wdata_q.delete();
    wdata_q.push_back(config_phy_addr_l());
    wdata_q.push_back(config_phy_addr_h());
    burst_write_reg_range(10'h40, 10'h44, wdata_q, 1);

    send_tx(status, wdata_q);

    seen1 = 0;
    repeat (WAIT_TX_CLK) begin
      @(posedge phy_vif.TX_CLK);
      #1;
      if (phy_vif.TX_EN === 1'b1) begin
        seen1 = 1;
        break;
      end
    end

    if (!seen1) begin
      `uvm_error(get_type_name(), "First baseline TX frame did not start")
    end
    else begin
      seen1 = 0;
      seen2 = 0;

      fork
        begin
          send_tx(status, wdata_q);
        end

        begin
          repeat (WAIT_TX_CLK) begin
            @(posedge phy_vif.TX_CLK);
            #1;
            if (phy_vif.TX_EN === 1'b0) begin
              time1 = tx_cycle;
              seen1 = 1;
              break;
            end
          end

          if (seen1) begin
            repeat (WAIT_TX_CLK) begin
              @(posedge phy_vif.TX_CLK);
              #1;
              if (phy_vif.TX_EN === 1'b1) begin
                time2 = tx_cycle;
                seen2 = 1;
                break;
              end
            end
          end
        end
      join

      if (!seen1 || !seen2) begin
        `uvm_error(get_type_name(), "Baseline TX gap was not observed")
      end
      else begin
        gap1 = time2 - time1;
        `uvm_info(get_type_name(),
          $sformatf("IFG: %0d", gap1),
          UVM_NONE)

        if (gap1 < IFG_TX_CLK)
          `uvm_error(get_type_name(),
            $sformatf("IFG is too short: expected>=%0d got=%0d",
                      IFG_TX_CLK, gap1))

        if (gap1 > (IFG_TX_CLK + IFG_TOL_TX_CLK))
          `uvm_error(get_type_name(),
            $sformatf("IFG is too long: expected around %0d got=%0d tolerance=%0d",
                      IFG_TX_CLK, gap1, IFG_TOL_TX_CLK))
      end

      wait (phy_vif.TX_EN === 1'b0);
      repeat (20) @(posedge phy_vif.TX_CLK);
    end

    send_tx(status, wdata_q);

    seen1 = 0;
    repeat (WAIT_TX_CLK) begin
      @(posedge phy_vif.TX_CLK);
      #1;
      if (phy_vif.TX_EN === 1'b1) begin
        seen1 = 1;
        break;
      end
    end

    if (!seen1) begin
      `uvm_error(get_type_name(), "First PAUSE test TX frame did not start")
    end
    else begin
      got_pause_irq = 0;
      seen0 = 0;
      seen1 = 0;
      seen2 = 0;
      seen_pause_timer = 0;
      pause_timer_capture = 16'd0;
      exp_pause_time = PAUSE_TIMER * PAUSE_QUANTA_TX_CLK;

      fork
        begin
          phy_pause_frame_seq pause_seq;
          pause_seq = phy_pause_frame_seq::type_id::create("pause_seq");
          assert(pause_seq.randomize() with {
            dst_mac     == 48'h01_80_C2_00_00_01;
            src_mac     == cfg.phy_addr;
            pause_timer == PAUSE_TIMER;
          })
          else `uvm_fatal(get_type_name(), "Failed to randomize PHY pause frame sequence")
          pause_seq.start(env.phy_agt.sequencer);
        end

        begin
          send_tx(status, wdata_q);
        end

        begin
          wait_interrupt_or_timeout(got_pause_irq);
        end

        begin
          bit [3:0] nibble_l;
          bit [7:0] rx_byte;
          int unsigned nib_idx;
          int unsigned byte_idx;

          repeat (WAIT_TX_CLK) begin
            @(posedge phy_vif.RX_CLK);
            #1;
            if (phy_vif.RX_DV === 1'b1) begin
              seen0 = 1;
              break;
            end
          end

          if (seen0) begin
            nib_idx = 0;
            seen0 = 0;
            repeat (WAIT_TX_CLK) begin
              if (phy_vif.RX_DV !== 1'b1) begin
                time0 = tx_cycle;
                time0_t = $time;
                seen0 = 1;
                break;
              end

              if (nib_idx[0] == 1'b0) begin
                nibble_l = phy_vif.RXD;
              end
              else begin
                rx_byte = {phy_vif.RXD, nibble_l};
                byte_idx = nib_idx >> 1;
                if (byte_idx == 24)
                  pause_timer_capture[15:8] = rx_byte;
                else if (byte_idx == 25) begin
                  pause_timer_capture[7:0] = rx_byte;
                  seen_pause_timer = 1;
                end
              end

              nib_idx++;
              @(posedge phy_vif.RX_CLK);
              #1;
            end
          end
        end

        begin
          repeat (WAIT_TX_CLK) begin
            @(posedge phy_vif.TX_CLK);
            #1;
            if (phy_vif.TX_EN === 1'b0) begin
              time1 = tx_cycle;
              seen1 = 1;
              break;
            end
          end

          if (seen1) begin
            repeat (WAIT_TX_CLK + exp_pause_time) begin
              @(posedge phy_vif.TX_CLK);
              #1;
              if (phy_vif.TX_EN === 1'b1) begin
                time2 = tx_cycle;
                time2_t = $time;
                seen2 = 1;
                break;
              end
            end
          end
        end
      join

      if (!got_pause_irq)
        `uvm_error(get_type_name(), "RX_PAUSE_SEEN interrupt was not asserted after valid RXD PAUSE frame")

      if (!seen0 || !seen1 || !seen2 || !seen_pause_timer) begin
        `uvm_error(get_type_name(), "PAUSE TX gap or timer was not observed")
      end
      else begin
        gap2 = time2 - time1;
        frame_pause_time = pause_timer_capture;

        if (gap2 < gap1) begin
          `uvm_error(get_type_name(),
            $sformatf("PAUSE gap is smaller than baseline gap: gap1=%0d gap2=%0d",
                      gap1, gap2))
        end
        else if (time1 < time0) begin
          `uvm_error(get_type_name(),
            $sformatf("PAUSE frame ended after current TX frame: time0=%0d time1=%0d",
                      time0, time1))
        end
        else begin
          pause_time_t = time2_t - time0_t;
          pause_time = (pause_time_t + (PAUSE_QUANTA_TIME / 2)) / PAUSE_QUANTA_TIME;
          delta = int'(pause_time) - int'(frame_pause_time);
          abs_delta = (delta < 0) ? -delta : delta;

          `uvm_info(get_type_name(),
            $sformatf("PAUSE: frame=%0d tx=%0d quanta", frame_pause_time, pause_time),
            UVM_NONE)

          if (abs_delta > PAUSE_TOL_QUANTA)
            `uvm_error(get_type_name(),
              $sformatf("PAUSE time mismatch: frame=%0d tx=%0d delta=%0d tolerance=%0d timer=0x%04h pause_time=%0t time0=%0d time1=%0d time2=%0d gap1=%0d gap2=%0d",
                        frame_pause_time, pause_time, delta, PAUSE_TOL_QUANTA,
                        pause_timer_capture, pause_time_t, time0, time1, time2,
                        gap1, gap2))
        end
      end

      wait (phy_vif.TX_EN === 1'b0);
      repeat (20) @(posedge phy_vif.TX_CLK);
    end

    tx_cycle_run = 0;
    phase.drop_objection(this);
  endtask
endclass
