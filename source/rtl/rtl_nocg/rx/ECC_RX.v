`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : csi2_ecc_rx
// Description   : CSI-2 Header ECC Decoder (Receiver Side)
//                 
//                 Extracts the 24-bit payload and 6-bit ECC from a 32-bit 
//                 received Low Level Protocol (LLP) packet header. Computes
//                 the syndrome to perform Single Error Correction and Double 
//                 Error Detection (SEC-DED) strictly adhering to the MIPI 
//                 CSI-2 standard (Section 9.5).
// Author        : Mohamed Zaher Fouda
// Architecture  : 1-Cycle Pipeline Latency.
//                 - Combinational XOR tree for ECC recalculation & syndrome.
//                 - Combinational decoding for error correction masks.
//                 - Registered outputs for timing closure downstream.
//-----------------------------------------------------------------------------

module csi2_ecc_rx (
    // -- Clocks & Resets --
    input  wire        i_clk,               // High-speed receiver byte clock
    input  wire        i_rst,               // Active-high synchronous reset

    // -- Upstream Interface (From D-PHY/Byte Unpacker) --
    input  wire        i_header_valid,      // Asserts when a new 32-bit header is available
    input  wire [31:0] i_received_header,   // {ECC[5:0], padded bits, WC[15:0], DI[7:0]}

    // -- Downstream Interface (To Protocol Engine) --
    output reg  [25:0] o_corrected_header,  // Verified/Corrected Data {2'b00, WC[15:0], DI[7:0]}
    output reg         o_single_bit_error,  // Asserts if a SEC was successfully applied
    output reg         o_double_bit_error,  // Asserts on fatal multi-bit error (DED)
    output reg         o_header_valid,      // Asserts 1 cycle after i_header_valid

    // -- Debug & Monitoring Observability --
    output wire [5:0]  o_ecc_rx,            // Extracted ECC from incoming packet
    output wire [5:0]  o_ecc_calc,          // Locally computed ECC based on payload
    output wire [5:0]  o_syndrome,          // XOR difference between rx and calc ECC
    output reg  [5:0]  o_error_index        // Syndrome passed through for debug tracing
);

    //=========================================================================
    // INTERNAL SIGNALS & WIRES
    //=========================================================================
    wire [25:0] d_rx;                       // Formatted 26-bit payload
    wire [5:0]  ecc_rx;                     // Received ECC
    wire [5:0]  ecc_calc;                   // Calculated ECC
    wire [5:0]  syndrome;                   // Error syndrome

    reg  [25:0] d_corr;                     // Combinational corrected data
    reg         single_err;                 // Combinational SEC flag
    reg         double_err;                 // Combinational DED flag

    //=========================================================================
    // PAYLOAD EXTRACTION & FORMATTING
    //=========================================================================
    // Isolate the 6-bit ECC from the MSB byte
    assign ecc_rx = i_received_header[29:24]; 
    
    // Construct the 26-bit data vector for the Hamming matrix.
    // Format: {2'b00 (Padding), WC_HI, WC_LO, DI}
    assign d_rx   = {i_received_header[7:0], 
                     i_received_header[15:8], 
                     i_received_header[23:16], 
                     i_received_header[31:30]}; 

    // Drive debug ports
    assign o_ecc_rx   = ecc_rx;
    assign o_ecc_calc = ecc_calc;
    assign o_syndrome = syndrome;

    //=========================================================================
    // ECC RECALCULATION & SYNDROME GENERATION (Combinational XOR Tree)
    //=========================================================================
    // Implements the standard MIPI CSI-2 SEC-DED polynomial matrix.
    // Generates the 6 parity bits concurrently.
    assign ecc_calc[0] = d_rx[0]^d_rx[1]^d_rx[2]^d_rx[4]^d_rx[5]^d_rx[7]^d_rx[10]^d_rx[11]^d_rx[13]^d_rx[16]^d_rx[20]^d_rx[21]^d_rx[22]^d_rx[23]^d_rx[24];
    assign ecc_calc[1] = d_rx[0]^d_rx[1]^d_rx[3]^d_rx[4]^d_rx[6]^d_rx[8]^d_rx[10]^d_rx[12]^d_rx[14]^d_rx[17]^d_rx[20]^d_rx[21]^d_rx[22]^d_rx[23]^d_rx[25];
    assign ecc_calc[2] = d_rx[0]^d_rx[2]^d_rx[3]^d_rx[5]^d_rx[6]^d_rx[9]^d_rx[11]^d_rx[12]^d_rx[15]^d_rx[18]^d_rx[20]^d_rx[21]^d_rx[22];
    assign ecc_calc[3] = d_rx[1]^d_rx[2]^d_rx[3]^d_rx[7]^d_rx[8]^d_rx[9]^d_rx[13]^d_rx[14]^d_rx[15]^d_rx[19]^d_rx[20]^d_rx[21]^d_rx[23]^d_rx[24]^d_rx[25]; 
    assign ecc_calc[4] = d_rx[4]^d_rx[5]^d_rx[6]^d_rx[7]^d_rx[8]^d_rx[9]^d_rx[16]^d_rx[17]^d_rx[18]^d_rx[19]^d_rx[20]^d_rx[24]^d_rx[25];
    assign ecc_calc[5] = d_rx[10]^d_rx[11]^d_rx[12]^d_rx[13]^d_rx[14]^d_rx[15]^d_rx[16]^d_rx[17]^d_rx[18]^d_rx[19]^d_rx[22]^d_rx[23]^d_rx[24]^d_rx[25]; 

    // Non-zero syndrome indicates an error occurred in transit.
    assign syndrome = ecc_rx ^ ecc_calc;

    //=========================================================================
    // ERROR DECODE & CORRECTION LOGIC (Combinational)
    //=========================================================================
    always @(*) begin
        // Default assignments to prevent latches
        d_corr        = d_rx;
        single_err    = 1'b0;
        double_err    = 1'b0;
        o_error_index = syndrome;

        if (syndrome == 6'h00) begin
            // Fast path: Data is clean
            single_err = 1'b0;
            double_err = 1'b0;
        end
        else begin
            // Decode syndrome against known column vectors of the Hamming matrix
            case (syndrome)
                // -------- Payload Data Bit Errors --------
                // If matched, flip the corresponding bit to correct (SEC)
                6'h07: begin d_corr[0]  = ~d_rx[0];  single_err = 1'b1; end
                6'h0B: begin d_corr[1]  = ~d_rx[1];  single_err = 1'b1; end
                6'h0D: begin d_corr[2]  = ~d_rx[2];  single_err = 1'b1; end
                6'h0E: begin d_corr[3]  = ~d_rx[3];  single_err = 1'b1; end
                6'h13: begin d_corr[4]  = ~d_rx[4];  single_err = 1'b1; end
                6'h15: begin d_corr[5]  = ~d_rx[5];  single_err = 1'b1; end
                6'h16: begin d_corr[6]  = ~d_rx[6];  single_err = 1'b1; end
                6'h19: begin d_corr[7]  = ~d_rx[7];  single_err = 1'b1; end
                6'h1A: begin d_corr[8]  = ~d_rx[8];  single_err = 1'b1; end
                6'h1C: begin d_corr[9]  = ~d_rx[9];  single_err = 1'b1; end
                6'h23: begin d_corr[10] = ~d_rx[10]; single_err = 1'b1; end
                6'h25: begin d_corr[11] = ~d_rx[11]; single_err = 1'b1; end
                6'h26: begin d_corr[12] = ~d_rx[12]; single_err = 1'b1; end
                6'h29: begin d_corr[13] = ~d_rx[13]; single_err = 1'b1; end
                6'h2A: begin d_corr[14] = ~d_rx[14]; single_err = 1'b1; end
                6'h2C: begin d_corr[15] = ~d_rx[15]; single_err = 1'b1; end
                6'h31: begin d_corr[16] = ~d_rx[16]; single_err = 1'b1; end
                6'h32: begin d_corr[17] = ~d_rx[17]; single_err = 1'b1; end
                6'h34: begin d_corr[18] = ~d_rx[18]; single_err = 1'b1; end
                6'h38: begin d_corr[19] = ~d_rx[19]; single_err = 1'b1; end
                6'h1F: begin d_corr[20] = ~d_rx[20]; single_err = 1'b1; end
                6'h0F: begin d_corr[21] = ~d_rx[21]; single_err = 1'b1; end
                6'h27: begin d_corr[22] = ~d_rx[22]; single_err = 1'b1; end
                6'h2B: begin d_corr[23] = ~d_rx[23]; single_err = 1'b1; end
                6'h39: begin d_corr[24] = ~d_rx[24]; single_err = 1'b1; end
                6'h3A: begin d_corr[25] = ~d_rx[25]; single_err = 1'b1; end

                // -------- ECC Parity Bit Errors --------
                // Payload is unaffected, but we must flag the SEC occurrence
                6'h01, 6'h02, 6'h04, 6'h08, 6'h10, 6'h20, 6'h2F, 6'h3D, 6'h3E: begin
                    single_err = 1'b1;
                end

                // -------- Fatal Multi-Bit Errors --------
                // Syndrome is non-zero but doesn't match any single-error signature
                default: begin
                    double_err = 1'b1;
                end
            endcase
        end
    end

    //=========================================================================
    // PIPELINE REGISTERS (Sequential)
    //=========================================================================
    // Introduces 1-cycle latency to ease timing paths on downstream logic
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            o_corrected_header <= 26'b0;
            o_single_bit_error <= 1'b0;
            o_double_bit_error <= 1'b0;
            o_header_valid     <= 1'b0;
        end
        else begin
            if (i_header_valid) begin
                o_corrected_header <= d_corr;
                o_single_bit_error <= single_err;
                o_double_bit_error <= double_err;
                o_header_valid     <= 1'b1;
            end
            else begin
                o_header_valid     <= 1'b0;
            end
        end
    end

endmodule
