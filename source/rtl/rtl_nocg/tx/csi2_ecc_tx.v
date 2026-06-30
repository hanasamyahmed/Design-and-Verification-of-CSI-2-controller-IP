`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : csi2_ecc_tx
// Description   : MIPI CSI-2 Packet Header ECC Generator (Transmitter Side)
//                 
//                 Implements a purely combinational XOR tree to generate the 
//                 6-bit Hamming Error Correction Code (ECC) required for the 
//                 CSI-2 Low Level Protocol (LLP) packet header. 
//
//                 The generated ECC provides Single Error Correction and Double 
//                 Error Detection (SEC-DED) for the 24-bit header payload 
//                 (Data Identifier + Word Count).
//
// Author        : Mohamed Zaher Fouda
// Architecture  : 0-Cycle Latency (Purely Combinational)
//                 - Implements standard MIPI CSI-2 Section 9.5 polynomial matrix
//                 - Fits directly into the TX packetizer header generation path
//-----------------------------------------------------------------------------

module csi2_ecc_tx (
    // -- Upstream Interface (From TX FSM / Packetizer) --
    // Input format mapped as a 26-bit vector padded for the Hamming matrix
    // Typically: {2'b00 (padding), WC[15:0], VC[1:0], DT[5:0]}
    input  wire [25:0] i_header_data, 

    // -- Downstream Interface (To TX D-PHY Data Path) --
    // Output format: 6-bit calculated ECC. 
    // (Note: Upper 2 bits of the transmitted byte must be padded to 2'b00 externally)
    output wire [5:0]  o_ecc
);

    //=========================================================================
    // ECC CALCULATION (Combinational XOR Tree)
    //=========================================================================
    // These equations evaluate the 6 independent parity bits concurrently, 
    // ensuring zero clock cycles of latency. The XOR network is strictly 
    // defined by the MIPI CSI-2 specification's parity generation matrix.

    // Parity Bit 0
    assign o_ecc[0] = i_header_data[0]  ^ i_header_data[1]  ^ i_header_data[2]  ^
                      i_header_data[4]  ^ i_header_data[5]  ^ i_header_data[7]  ^
                      i_header_data[10] ^ i_header_data[11] ^ i_header_data[13] ^
                      i_header_data[16] ^ i_header_data[20] ^ i_header_data[21] ^
                      i_header_data[22] ^ i_header_data[23] ^ i_header_data[24];

    // Parity Bit 1
    assign o_ecc[1] = i_header_data[0]  ^ i_header_data[1]  ^ i_header_data[3]  ^
                      i_header_data[4]  ^ i_header_data[6]  ^ i_header_data[8]  ^
                      i_header_data[10] ^ i_header_data[12] ^ i_header_data[14] ^
                      i_header_data[17] ^ i_header_data[20] ^ i_header_data[21] ^
                      i_header_data[22] ^ i_header_data[23] ^ i_header_data[25];

    // Parity Bit 2
    assign o_ecc[2] = i_header_data[0]  ^ i_header_data[2]  ^ i_header_data[3]  ^
                      i_header_data[5]  ^ i_header_data[6]  ^ i_header_data[9]  ^
                      i_header_data[11] ^ i_header_data[12] ^ i_header_data[15] ^
                      i_header_data[18] ^ i_header_data[20] ^ i_header_data[21] ^
                      i_header_data[22];

    // Parity Bit 3
    assign o_ecc[3] = i_header_data[1]  ^ i_header_data[2]  ^ i_header_data[3]  ^
                      i_header_data[7]  ^ i_header_data[8]  ^ i_header_data[9]  ^
                      i_header_data[13] ^ i_header_data[14] ^ i_header_data[15] ^
                      i_header_data[19] ^ i_header_data[20] ^ i_header_data[21] ^
                      i_header_data[23] ^ i_header_data[24] ^ i_header_data[25];

    // Parity Bit 4
    assign o_ecc[4] = i_header_data[4]  ^ i_header_data[5]  ^ i_header_data[6]  ^
                      i_header_data[7]  ^ i_header_data[8]  ^ i_header_data[9]  ^
                      i_header_data[16] ^ i_header_data[17] ^ i_header_data[18] ^
                      i_header_data[19] ^ i_header_data[20] ^ i_header_data[24] ^
                      i_header_data[25];

    // Parity Bit 5
    assign o_ecc[5] = i_header_data[10] ^ i_header_data[11] ^ i_header_data[12] ^
                      i_header_data[13] ^ i_header_data[14] ^ i_header_data[15] ^
                      i_header_data[16] ^ i_header_data[17] ^ i_header_data[18] ^
                      i_header_data[19] ^ i_header_data[22] ^ i_header_data[23] ^
                      i_header_data[24] ^ i_header_data[25];

endmodule
