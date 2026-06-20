`timescale 1ns / 1ps

// CRC generation module for Ethernet frames (IEEE 802.3)
// Implements CRC-32 using Ethernet polynomial: x^32+x^26+x^23+x^22+x^16+x^12+x^11+x^10+x^8+x^7+x^5+x^4+x^2+x+1
// Data is consumed 4 bits at a time (nibble-wise)

module eth_crc (
    input wire              i_clk,
    input wire              i_rst_n,

    input wire [3:0]        i_data,     // 4-bit data input, bit 0 is serial first
    input wire              i_enable,   // Enable CRC calculation
    input wire              i_init,     // Initialize CRC to all-1s

    output wire [31:0]      o_crc,      // Current CRC value
    output wire             o_crc_err   // Set when CRC != expected magic value
);

    // =========================================================
    // CRC-32 NEXT STATE LOGIC
    // =========================================================
    // Parallel CRC calculation (4 bits per cycle)
    // Generated from CRC-32 polynomial for Ethernet
    // Format: CrcNext = f(Data, Crc) when Enable=1.
    // When Enable=0, the CRC register holds its value.

    wire [31:0] w_crc_calc;
    wire [31:0] w_crc_next;

    assign w_crc_calc[0]  = i_data[0] ^ o_crc[28];
    assign w_crc_calc[1]  = i_data[1] ^ i_data[0] ^ o_crc[28] ^ o_crc[29];
    assign w_crc_calc[2]  = i_data[2] ^ i_data[1] ^ i_data[0] ^ o_crc[28] ^ o_crc[29] ^ o_crc[30];
    assign w_crc_calc[3]  = i_data[3] ^ i_data[2] ^ i_data[1] ^ o_crc[29] ^ o_crc[30] ^ o_crc[31];
    assign w_crc_calc[4]  = i_data[3] ^ i_data[2] ^ i_data[0] ^ o_crc[28] ^ o_crc[30] ^ o_crc[31] ^ o_crc[0];
    assign w_crc_calc[5]  = i_data[3] ^ i_data[1] ^ i_data[0] ^ o_crc[28] ^ o_crc[29] ^ o_crc[31] ^ o_crc[1];
    assign w_crc_calc[6]  = i_data[2] ^ i_data[1] ^ o_crc[29] ^ o_crc[30] ^ o_crc[2];
    assign w_crc_calc[7]  = i_data[3] ^ i_data[2] ^ i_data[0] ^ o_crc[28] ^ o_crc[30] ^ o_crc[31] ^ o_crc[3];
    assign w_crc_calc[8]  = i_data[3] ^ i_data[1] ^ i_data[0] ^ o_crc[28] ^ o_crc[29] ^ o_crc[31] ^ o_crc[4];
    assign w_crc_calc[9]  = i_data[2] ^ i_data[1] ^ o_crc[29] ^ o_crc[30] ^ o_crc[5];
    assign w_crc_calc[10] = i_data[3] ^ i_data[2] ^ i_data[0] ^ o_crc[28] ^ o_crc[30] ^ o_crc[31] ^ o_crc[6];
    assign w_crc_calc[11] = i_data[3] ^ i_data[1] ^ i_data[0] ^ o_crc[28] ^ o_crc[29] ^ o_crc[31] ^ o_crc[7];
    assign w_crc_calc[12] = i_data[2] ^ i_data[1] ^ i_data[0] ^ o_crc[28] ^ o_crc[29] ^ o_crc[30] ^ o_crc[8];
    assign w_crc_calc[13] = i_data[3] ^ i_data[2] ^ i_data[1] ^ o_crc[29] ^ o_crc[30] ^ o_crc[31] ^ o_crc[9];
    assign w_crc_calc[14] = i_data[3] ^ i_data[2] ^ o_crc[30] ^ o_crc[31] ^ o_crc[10];
    assign w_crc_calc[15] = i_data[3] ^ o_crc[31] ^ o_crc[11];
    assign w_crc_calc[16] = i_data[0] ^ o_crc[28] ^ o_crc[12];
    assign w_crc_calc[17] = i_data[1] ^ o_crc[29] ^ o_crc[13];
    assign w_crc_calc[18] = i_data[2] ^ o_crc[30] ^ o_crc[14];
    assign w_crc_calc[19] = i_data[3] ^ o_crc[31] ^ o_crc[15];
    assign w_crc_calc[20] = o_crc[16];
    assign w_crc_calc[21] = o_crc[17];
    assign w_crc_calc[22] = i_data[0] ^ o_crc[28] ^ o_crc[18];
    assign w_crc_calc[23] = i_data[1] ^ i_data[0] ^ o_crc[29] ^ o_crc[28] ^ o_crc[19];
    assign w_crc_calc[24] = i_data[2] ^ i_data[1] ^ o_crc[30] ^ o_crc[29] ^ o_crc[20];
    assign w_crc_calc[25] = i_data[3] ^ i_data[2] ^ o_crc[31] ^ o_crc[30] ^ o_crc[21];
    assign w_crc_calc[26] = i_data[3] ^ i_data[0] ^ o_crc[31] ^ o_crc[28] ^ o_crc[22];
    assign w_crc_calc[27] = i_data[1] ^ o_crc[29] ^ o_crc[23];
    assign w_crc_calc[28] = i_data[2] ^ o_crc[30] ^ o_crc[24];
    assign w_crc_calc[29] = i_data[3] ^ o_crc[31] ^ o_crc[25];
    assign w_crc_calc[30] = o_crc[26];
    assign w_crc_calc[31] = o_crc[27];

    assign w_crc_next = i_enable ? w_crc_calc : o_crc;

    // =========================================================
    // CRC REGISTER (32-bit)
    // =========================================================
    // Reset or Initialize: all-1s (IEEE 802.3 standard seed)
    // Update: calculate next CRC when enabled, otherwise hold.

    reg [31:0] r_crc;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_crc <= 32'hFFFFFFFF;
        else if (i_init)
            r_crc <= 32'hFFFFFFFF;
        else
            r_crc <= w_crc_next;
    end

    assign o_crc = r_crc;

    // =========================================================
    // CRC ERROR DETECTION
    // =========================================================
    // Magic number 0xC704DD7B is the expected CRC for a valid frame
    // (all-1s seed, correct CRC bytes appended and inverted)

    assign o_crc_err = (r_crc != 32'hC704DD7B);

endmodule
