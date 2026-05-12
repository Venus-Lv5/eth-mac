`timescale 1ns / 1ps

module eth_interrupt (
    input wire                  i_clk,
    input wire                  i_rst_n,

    // Clock for MAC/PHY domain (external)
    input wire                  i_mac_clk,

    // Interrupt request inputs (from TX/RX DMA/MAC)
    // These may come from different clock domains
    input wire                  i_tx_done,      // TX buffer transmitted (from TX DMA, same clk)
    input wire                  i_tx_err,      // TX error (from TX DMA, same clk)
    input wire                  i_rx_done,      // RX buffer received (from RX DMA, same clk)
    input wire                  i_rx_err,       // RX error (from RX DMA, same clk)
    input wire                  i_rx_busy,      // RX buffer not ready (from MAC, i_mac_clk domain)
    input wire                  i_tx_ctrl_done, // TX PAUSE frame sent (from MAC)
    input wire                  i_rx_ctrl_done, // RX PAUSE frame received (from MAC)

    // Interrupt mask/enable from register file (INT_EN register)
    input wire [6:0]            i_int_en,       // bit[6:0]: enable for each interrupt

    // Software control: write to INT_STATUS to clear/set interrupts
    input wire                  i_status_wr,
    input wire [6:0]            i_status_wr_data, // Data written to INT_STATUS

    // Final interrupt output to system
    output wire                 o_irq,

    // Interrupt status for software to read (reflects internal sticky flags)
    output wire [6:0]           o_irq_flags
);

    // =========================================================
    // INTERRUPT SOURCE MAPPING
    // =========================================================
    // bit[0]: TX_DONE     - Transmit complete
    // bit[1]: TX_ERR      - Transmit error
    // bit[2]: RX_DONE     - Receive complete
    // bit[3]: RX_ERR      - Receive error
    // bit[4]: RX_BUSY     - RX buffer unavailable
    // bit[5]: TX_CTRL     - TX control frame (PAUSE) complete
    // bit[6]: RX_CTRL     - RX control frame (PAUSE) received

    // =========================================================
    // CDC STAGE 1: Synchronize signals from i_mac_clk to i_clk
    // Following code gốc pattern: 3-stage synchronizer + edge detection
    // =========================================================

    // --- i_rx_busy CDC (i_mac_clk → i_clk) ---
    // Same pattern as Busy_IRQ in eth_wishbone.v
    reg r_rx_busy_mac;
    reg r_rx_busy_sync1;
    reg r_rx_busy_sync2;
    reg r_rx_busy_sync3;
    reg r_rx_busy_syncb1;  // For clear path back to mac_clk
    reg r_rx_busy_syncb2;

    // Latch in source domain (i_mac_clk)
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_busy_mac <= 1'b0;
        else
            r_rx_busy_mac <= i_rx_busy;
    end

    // Sync chain in destination domain (i_clk)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_busy_sync1 <= 1'b0;
            r_rx_busy_sync2 <= 1'b0;
            r_rx_busy_sync3 <= 1'b0;
        end else begin
            r_rx_busy_sync1 <= r_rx_busy_mac;
            r_rx_busy_sync2 <= r_rx_busy_sync1;
            r_rx_busy_sync3 <= r_rx_busy_sync2;
        end
    end

    // Sync chain for clear signal back to mac_clk
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_busy_syncb1 <= 1'b0;
            r_rx_busy_syncb2 <= 1'b0;
        end else begin
            r_rx_busy_syncb1 <= r_rx_busy_sync2;
            r_rx_busy_syncb2 <= r_rx_busy_syncb1;
        end
    end

    // Edge detection: pulse when sync2 goes high and sync3 is low
    wire w_rx_busy_pulse;
    assign w_rx_busy_pulse = r_rx_busy_sync2 & ~r_rx_busy_sync3;

    // --- i_tx_ctrl_done CDC (i_mac_clk → i_clk) ---
    // Same pattern as TxC_IRQ in eth_registers.v
    reg r_tx_ctrl_mac;
    reg r_tx_ctrl_sync1;
    reg r_tx_ctrl_sync2;
    reg r_tx_ctrl_sync3;

    // Latch in source domain (i_mac_clk)
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_tx_ctrl_mac <= 1'b0;
        else
            r_tx_ctrl_mac <= i_tx_ctrl_done;
    end

    // Sync chain in destination domain (i_clk)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_tx_ctrl_sync1 <= 1'b0;
            r_tx_ctrl_sync2 <= 1'b0;
            r_tx_ctrl_sync3 <= 1'b0;
        end else begin
            r_tx_ctrl_sync1 <= r_tx_ctrl_mac;
            r_tx_ctrl_sync2 <= r_tx_ctrl_sync1;
            r_tx_ctrl_sync3 <= r_tx_ctrl_sync2;
        end
    end

    // Edge detection
    wire w_tx_ctrl_pulse;
    assign w_tx_ctrl_pulse = r_tx_ctrl_sync2 & ~r_tx_ctrl_sync3;

    // --- i_rx_ctrl_done CDC (i_mac_clk → i_clk) ---
    // Same pattern as RxC_IRQ in eth_registers.v
    reg r_rx_ctrl_mac;
    reg r_rx_ctrl_sync1;
    reg r_rx_ctrl_sync2;
    reg r_rx_ctrl_sync3;

    // Latch in source domain (i_mac_clk)
    always @(posedge i_mac_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_rx_ctrl_mac <= 1'b0;
        else
            r_rx_ctrl_mac <= i_rx_ctrl_done;
    end

    // Sync chain in destination domain (i_clk)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_rx_ctrl_sync1 <= 1'b0;
            r_rx_ctrl_sync2 <= 1'b0;
            r_rx_ctrl_sync3 <= 1'b0;
        end else begin
            r_rx_ctrl_sync1 <= r_rx_ctrl_mac;
            r_rx_ctrl_sync2 <= r_rx_ctrl_sync1;
            r_rx_ctrl_sync3 <= r_rx_ctrl_sync2;
        end
    end

    // Edge detection
    wire w_rx_ctrl_pulse;
    assign w_rx_ctrl_pulse = r_rx_ctrl_sync2 & ~r_rx_ctrl_sync3;

    // =========================================================
    // CDC STAGE 2: Generate synchronized raw interrupt requests
    // =========================================================
    // Signals from same clock domain (TX/RX DMA) - no CDC needed
    wire w_tx_done_synced;
    wire w_tx_err_synced;
    wire w_rx_done_synced;
    wire w_rx_err_synced;

    assign w_tx_done_synced = i_tx_done;
    assign w_tx_err_synced  = i_tx_err;
    assign w_rx_done_synced = i_rx_done;
    assign w_rx_err_synced  = i_rx_err;

    // Combined raw interrupt signals (after CDC for cross-domain signals)
    wire [6:0] w_irq_raw;
    assign w_irq_raw = {
        w_rx_ctrl_pulse,   // bit[6]: RX_CTRL
        w_tx_ctrl_pulse,  // bit[5]: TX_CTRL
        w_rx_busy_pulse,  // bit[4]: RX_BUSY
        w_rx_err_synced,  // bit[3]: RX_ERR
        w_rx_done_synced, // bit[2]: RX_DONE
        w_tx_err_synced,  // bit[1]: TX_ERR
        w_tx_done_synced   // bit[0]: TX_DONE
    };

    // =========================================================
    // STICKY INTERRUPT FLAGS (Write 1 to Clear)
    // =========================================================
    // Each flag stays high once set until software clears it
    // Following code gốc: r_irq_flag behavior
    reg [6:0] r_irq_flag;

    // Set flags on interrupt request
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_irq_flag <= 7'b0;
        end else if (i_status_wr) begin
            // Clear flags where data bit is 1 (R/W1C behavior)
            r_irq_flag <= r_irq_flag & ~i_status_wr_data;
        end else begin
            // Set on new interrupt request (sticky)
            r_irq_flag <= r_irq_flag | w_irq_raw;
        end
    end

    // =========================================================
    // INTERRUPT STATUS OUTPUT
    // =========================================================
    assign o_irq_flags = r_irq_flag;

    // =========================================================
    // FINAL INTERRUPT OUTPUT
    // int_o = OR(irq_flag[i] & int_en[i])
    // Following code gốc: int_o = irq_txb & INT_MASK[0] | ...
    // =========================================================
    assign o_irq = |(r_irq_flag & i_int_en);

endmodule
