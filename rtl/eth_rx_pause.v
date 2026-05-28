`timescale 1ns/1ps

module eth_rx_pause (
    // Global
    input  wire        i_mrx_clk,
    input  wire        i_mtx_clk,
    input  wire        i_rst_n,

    // RX
    input  wire        i_rx_valid,
    input  wire  [7:0] i_rx_data,
    input  wire        i_rx_start,
    input  wire        i_rx_end,
    input  wire        i_rx_flow,
    input  wire        i_rx_good,
    input  wire        i_rx_len_ok,

    // TX
    input  wire        i_tx_done,
    input  wire        i_tx_abort,
    input  wire        i_tx_start,
    input  wire        i_tx_used_data,

    // Config
    input  wire [47:0] i_mac_addr,

    // Output
    output reg         o_rx_pause_done,
    output reg         o_pause
);

    localparam PAUSE_DA     = 48'h0180C2000001;
    localparam PAUSE_TYPE   = 16'h8808;
    localparam PAUSE_OPCODE = 16'h0001;

    // RX domain registers
    reg [4:0]   r_byte_cnt;
    reg         r_detect_window;
    reg         r_addr_ok;
    reg         r_type_ok;
    reg         r_opcode_ok;
    reg         r_pause_frame;
    reg         r_pause_frame_waddr;
    reg [15:0]  r_timer_assembled;
    reg [15:0]  r_timer_latched;
    reg [15:0]  r_pause_timer;
    reg         r_slot_div;
    reg [5:0]   r_slot_timer;
    reg         r_timer_eq0;

    // TX domain registers
    reg         r_timer_eq0_s1;
    reg         r_timer_eq0_s2;
    reg         r_pause;

    wire        w_rx_rst;
    wire        w_tx_rst;
    wire        w_slot_end;

    // Byte position flags (same as original: RxValid & cnt==X)
    wire        w_byte_eq0;
    wire        w_byte_eq1;
    wire        w_byte_eq2;
    wire        w_byte_eq3;
    wire        w_byte_eq4;
    wire        w_byte_eq5;
    wire        w_byte_eq12;
    wire        w_byte_eq13;
    wire        w_byte_eq14;
    wire        w_byte_eq15;
    wire        w_byte_eq16;
    wire        w_byte_eq17;
    wire        w_byte_eq18;

    assign w_rx_rst = ~i_rst_n;
    assign w_tx_rst = ~i_rst_n;

    // Byte position flags (matching original logic)
    assign w_byte_eq0  = i_rx_valid & (r_byte_cnt == 5'h0);
    assign w_byte_eq1  = i_rx_valid & (r_byte_cnt == 5'h1);
    assign w_byte_eq2  = i_rx_valid & (r_byte_cnt == 5'h2);
    assign w_byte_eq3  = i_rx_valid & (r_byte_cnt == 5'h3);
    assign w_byte_eq4  = i_rx_valid & (r_byte_cnt == 5'h4);
    assign w_byte_eq5  = i_rx_valid & (r_byte_cnt == 5'h5);
    assign w_byte_eq12 = i_rx_valid & (r_byte_cnt == 5'hC);
    assign w_byte_eq13 = i_rx_valid & (r_byte_cnt == 5'hD);
    assign w_byte_eq14 = i_rx_valid & (r_byte_cnt == 5'hE);
    assign w_byte_eq15 = i_rx_valid & (r_byte_cnt == 5'hF);
    assign w_byte_eq16 = i_rx_valid & (r_byte_cnt == 5'h10);
    assign w_byte_eq17 = i_rx_valid & (r_byte_cnt == 5'h11);
    assign w_byte_eq18 = i_rx_valid & (r_byte_cnt == 5'h12) & r_detect_window;

    // Byte counter (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_byte_cnt <= 5'h0;
        else if (i_rx_end)
            r_byte_cnt <= 5'h0;
        else if (i_rx_valid & r_detect_window & ~w_byte_eq18)
            r_byte_cnt <= r_byte_cnt + 1'b1;
    end

    // Detection window (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_detect_window <= 1'b1;
        else if (w_byte_eq18)
            r_detect_window <= 1'b0;
        else if (i_rx_end)
            r_detect_window <= 1'b1;
    end

    // Address check (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_addr_ok <= 1'b0;
        else if (i_rx_end)
            r_addr_ok <= 1'b0;
        else if (r_detect_window & w_byte_eq0)
            r_addr_ok <= (i_rx_data == PAUSE_DA[47:40]) | (i_rx_data == i_mac_addr[47:40]);
        else if (r_detect_window & w_byte_eq1)
            r_addr_ok <= r_addr_ok & ((i_rx_data == PAUSE_DA[39:32]) | (i_rx_data == i_mac_addr[39:32]));
        else if (r_detect_window & w_byte_eq2)
            r_addr_ok <= r_addr_ok & ((i_rx_data == PAUSE_DA[31:24]) | (i_rx_data == i_mac_addr[31:24]));
        else if (r_detect_window & w_byte_eq3)
            r_addr_ok <= r_addr_ok & ((i_rx_data == PAUSE_DA[23:16]) | (i_rx_data == i_mac_addr[23:16]));
        else if (r_detect_window & w_byte_eq4)
            r_addr_ok <= r_addr_ok & ((i_rx_data == PAUSE_DA[15:8]) | (i_rx_data == i_mac_addr[15:8]));
        else if (r_detect_window & w_byte_eq5)
            r_addr_ok <= r_addr_ok & ((i_rx_data == PAUSE_DA[7:0]) | (i_rx_data == i_mac_addr[7:0]));
    end

    // Type check (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_type_ok <= 1'b0;
        else if (i_rx_end)
            r_type_ok <= 1'b0;
        else if (r_detect_window & w_byte_eq12)
            r_type_ok <= w_byte_eq12 & (i_rx_data == PAUSE_TYPE[15:8]);
        else if (r_detect_window & w_byte_eq13)
            r_type_ok <= w_byte_eq13 & (i_rx_data == PAUSE_TYPE[7:0]) & r_type_ok;
    end

    // Opcode check (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_opcode_ok <= 1'b0;
        else if (w_byte_eq16)
            r_opcode_ok <= 1'b0;
        else if (r_detect_window & w_byte_eq14)
            r_opcode_ok <= w_byte_eq14 & (i_rx_data == 8'h00);
        else if (r_detect_window & w_byte_eq15)
            r_opcode_ok <= w_byte_eq15 & (i_rx_data == 8'h01) & r_opcode_ok;
    end

    // Pause frame with address check (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_pause_frame_waddr <= 1'b0;
        else if (i_rx_end)
            r_pause_frame_waddr <= 1'b0;
        else if (w_byte_eq16 & r_type_ok & r_opcode_ok & r_addr_ok)
            r_pause_frame_waddr <= 1'b1;
    end

    // Pause frame without address check (for interrupt - matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_pause_frame <= 1'b0;
        else if (w_byte_eq16 & r_type_ok & r_opcode_ok)
            r_pause_frame <= 1'b1;
        else if (i_rx_end)
            r_pause_frame <= 1'b0;
    end

    // Assemble timer value (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_timer_assembled <= 16'h0;
        else if (i_rx_start)
            r_timer_assembled <= 16'h0;
        else if (r_detect_window & w_byte_eq16)
            r_timer_assembled[15:8] <= i_rx_data;
        else if (r_detect_window & w_byte_eq17)
            r_timer_assembled[7:0] <= i_rx_data;
    end

    // Latch timer (matching original logic - latch at byte 18)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_timer_latched <= 16'h0;
        else if (r_detect_window & r_pause_frame_waddr & w_byte_eq18)
            r_timer_latched <= r_timer_assembled;
        else if (i_rx_end)
            r_timer_latched <= 16'h0;
    end

    // Slot divider (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_slot_div <= 1'b0;
        else if (|r_pause_timer & i_rx_flow)
            r_slot_div <= ~r_slot_div;
        else
            r_slot_div <= 1'b0;
    end

    assign w_slot_end = &r_slot_timer & r_slot_div;

    // Slot timer (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_slot_timer <= 6'h0;
        else if (r_slot_div)
            r_slot_timer <= r_slot_timer + 1'b1;
    end

    // Pause timer (matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            r_pause_timer <= 16'h0;
        else if (r_detect_window & r_pause_frame_waddr & w_byte_eq18)
            r_pause_timer <= r_timer_assembled;
        else if (w_slot_end & |r_pause_timer)
            r_pause_timer <= r_pause_timer - 1'b1;
    end

    assign r_timer_eq0 = ~(|r_pause_timer);

    // RX pause done (for interrupt - matching original logic)
    always @(posedge i_mrx_clk or posedge w_rx_rst) begin
        if (w_rx_rst)
            o_rx_pause_done <= 1'b0;
        else if (i_rx_end & r_pause_frame_waddr)
            o_rx_pause_done <= 1'b1;
        else
            o_rx_pause_done <= 1'b0;
    end

    // CDC: timer status to MTxClk domain (matching original logic)
    always @(posedge i_mtx_clk or posedge w_tx_rst) begin
        if (w_tx_rst) begin
            r_timer_eq0_s1 <= 1'b1;
            r_timer_eq0_s2 <= 1'b1;
        end else begin
            r_timer_eq0_s1 <= r_timer_eq0;
            r_timer_eq0_s2 <= r_timer_eq0_s1;
        end
    end

    // Pause signal (matching original logic)
    always @(posedge i_mtx_clk or posedge w_tx_rst) begin
        if (w_tx_rst)
            r_pause <= 1'b0;
        else if ((i_tx_done | i_tx_abort | ~i_tx_used_data) & ~i_tx_start)
            r_pause <= i_rx_flow & ~r_timer_eq0_s2;
    end

    assign o_pause = r_pause;

endmodule
