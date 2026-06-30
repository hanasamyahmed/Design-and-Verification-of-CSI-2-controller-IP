`timescale 1ns / 1ps

// ============================================================================
// File Name   : mipi_scrambler.v
// Project     : MIPI CSI Controller IP
// Description : Data Scrambler Module for MIPI Transmitter.
//               Reduces Electromagnetic Interference (EMI) by scrambling the 
//               outgoing data stream using a 16-bit LFSR. Implements parallel 
//               feedback logic (unrolling) to process one full byte per clock 
//               cycle, matching high-speed PPI requirements.
// Standard    : Based on MIPI D-PHY/C-PHY Scrambling Polynomial Definitions.
// ============================================================================

module mipi_scrambler #(
    parameter [15:0] LANE_SEED = 16'h0810 
)(
    // -------------------------------------------------------------------------
    // System Clock & Reset
    // ---------------------------------------------------------
    input  wire        i_clk,
    input  wire        i_rst_n,
    
    // -------------------------------------------------------------------------
    // Control & Input Data Stream
    // ---------------------------------------------------------
    input  wire        i_packet_active,  // Resets LFSR to SEED when idle
    input  wire [7:0]  i_lane_data,      // Raw data byte from Distributor
    input  wire        i_lane_vld,       // Data valid indicator
    
    // -------------------------------------------------------------------------
    // Scrambled Data Outputs
    // ---------------------------------------------------------
    output wire [7:0]  o_scrambled_data,
    output wire        o_lane_vld_out
);

    // 16-bit Linear Feedback Shift Register (LFSR) State
    reg  [15:0] r_lfsr_state;
    
    // Intermediate wires for Parallel Logic evaluation
    wire [7:0]  w_key_stream;
    wire [7:0]  w_fb;
    wire [15:0] w_lfsr_next;

    // =========================================================================
    // 1. Hardware Unrolling (Parallel Feedback Logic)
    // Description: Calculates 8 bits of LFSR feedback concurrently using 
    //              Combinational Logic to support byte-aligned scrambling. 
    //              This prevents multiple-assignment warnings (W415a) and 
    //              optimizes timing for high-frequency operation.
    // =========================================================================
    assign w_fb[0] = r_lfsr_state[0] ^ r_lfsr_state[3] ^ r_lfsr_state[4] ^ r_lfsr_state[5];
    assign w_fb[1] = r_lfsr_state[1] ^ r_lfsr_state[4] ^ r_lfsr_state[5] ^ r_lfsr_state[6];
    assign w_fb[2] = r_lfsr_state[2] ^ r_lfsr_state[5] ^ r_lfsr_state[6] ^ r_lfsr_state[7];
    assign w_fb[3] = r_lfsr_state[3] ^ r_lfsr_state[6] ^ r_lfsr_state[7] ^ r_lfsr_state[8];
    assign w_fb[4] = r_lfsr_state[4] ^ r_lfsr_state[7] ^ r_lfsr_state[8] ^ r_lfsr_state[9];
    assign w_fb[5] = r_lfsr_state[5] ^ r_lfsr_state[8] ^ r_lfsr_state[9] ^ r_lfsr_state[10];
    assign w_fb[6] = r_lfsr_state[6] ^ r_lfsr_state[9] ^ r_lfsr_state[10] ^ r_lfsr_state[11];
    assign w_fb[7] = r_lfsr_state[7] ^ r_lfsr_state[10] ^ r_lfsr_state[11] ^ r_lfsr_state[12];

    // Keystream is derived from the current LFSR state
    assign w_key_stream = r_lfsr_state[7:0];

    // Compute the next state for the next clock cycle
    assign w_lfsr_next  = {w_fb[7], w_fb[6], w_fb[5], w_fb[4], w_fb[3], w_fb[2], w_fb[1], w_fb[0], r_lfsr_state[15:8]};

    // =========================================================================
    // 2. LFSR State Management
    // Description: Synchronizes the LFSR state transitions. 
    //              - Reset/Idle: Reloads the 'LANE_SEED'.
    //              - Active Scrambling: Advances to 'w_lfsr_next' on every valid byte.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)                 r_lfsr_state <= LANE_SEED;
        else if (!i_packet_active)    r_lfsr_state <= LANE_SEED; 
        else if (i_lane_vld)          r_lfsr_state <= w_lfsr_next;
    end

    // =========================================================================
    // 3. Data Scrambling Operation (XOR)
    // Description: Scrambles the input data byte by XORing it with the 
    //              generated key-stream. Output is zeroed when not valid.
    // =========================================================================
    assign o_scrambled_data = i_lane_vld ? (i_lane_data ^ w_key_stream) : 8'h00;
    assign o_lane_vld_out   = i_lane_vld;

endmodule

