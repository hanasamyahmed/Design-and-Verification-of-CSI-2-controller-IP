`timescale 1ns / 1ps

// ============================================================================
// File Name   : mipi_descrambler.v
// Project     : MIPI CSI Controller IP
// Description : Data Descrambler Module for MIPI Receiver.
//               Reverses the scrambling process applied at the transmitter 
//               side using a 16-bit Linear Feedback Shift Register (LFSR). 
//               Implements hardware unrolling to evaluate 8 bits of key-stream 
//               per clock cycle, ensuring high throughput.
// Standard    : Based on MIPI D-PHY/C-PHY Scrambling Polynomial Definitions.
// ============================================================================

module mipi_descrambler #(
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
    input  wire        i_packet_active,  // Resets LFSR to SEED when de-asserted
    input  wire [7:0]  i_scrambled_data, 
    input  wire        i_lane_vld,       // Data valid for the current lane
    
    // -------------------------------------------------------------------------
    // Descrambled Data Outputs
    // ---------------------------------------------------------
    output wire [7:0]  o_descrambled_data,
    output wire        o_lane_vld_out
);

    // LFSR State Register
    reg  [15:0] r_lfsr_state;
    
    // Intermediate wires for Parallel Logic evaluation
    wire [7:0]  w_key_stream;
    wire [7:0]  w_fb;
    wire [15:0] w_lfsr_next;

    // =========================================================================
    // 1. Hardware Unrolling (Parallel Feedback Evaluation)
    // Description: Calculates 8 bits of LFSR feedback in a single cycle using 
    //              Combinational Logic. This eliminates the need for 'for-loops' 
    //              and avoids multiple driver issues during synthesis.
    // Polynomial: Evaluates the specific MIPI-standard scrambling taps.
    // =========================================================================
    assign w_fb[0] = r_lfsr_state[0] ^ r_lfsr_state[3] ^ r_lfsr_state[4] ^ r_lfsr_state[5];
    assign w_fb[1] = r_lfsr_state[1] ^ r_lfsr_state[4] ^ r_lfsr_state[5] ^ r_lfsr_state[6];
    assign w_fb[2] = r_lfsr_state[2] ^ r_lfsr_state[5] ^ r_lfsr_state[6] ^ r_lfsr_state[7];
    assign w_fb[3] = r_lfsr_state[3] ^ r_lfsr_state[6] ^ r_lfsr_state[7] ^ r_lfsr_state[8];
    assign w_fb[4] = r_lfsr_state[4] ^ r_lfsr_state[7] ^ r_lfsr_state[8] ^ r_lfsr_state[9];
    assign w_fb[5] = r_lfsr_state[5] ^ r_lfsr_state[8] ^ r_lfsr_state[9] ^ r_lfsr_state[10];
    assign w_fb[6] = r_lfsr_state[6] ^ r_lfsr_state[9] ^ r_lfsr_state[10] ^ r_lfsr_state[11];
    assign w_fb[7] = r_lfsr_state[7] ^ r_lfsr_state[10] ^ r_lfsr_state[11] ^ r_lfsr_state[12];

    // The key-stream is the lowest 8 bits of the current state
    assign w_key_stream = r_lfsr_state[7:0];

    // Construct the next 16-bit state by shifting and inserting feedback bits
    assign w_lfsr_next  = {w_fb[7], w_fb[6], w_fb[5], w_fb[4], w_fb[3], w_fb[2], w_fb[1], w_fb[0], r_lfsr_state[15:8]};

    // =========================================================================
    // 2. LFSR State Controller
    // Description: Manages initialization and state transitions.
    //              - Reset or Idle: Re-initializes state to the 'LANE_SEED'.
    //              - Active Reception: Advances the LFSR state per valid byte.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)                 r_lfsr_state <= LANE_SEED;
        else if (!i_packet_active)    r_lfsr_state <= LANE_SEED;
        else if (i_lane_vld)          r_lfsr_state <= w_lfsr_next;
    end

    // =========================================================================
    // 3. Descrambling Operation (XOR)
    // Description: Recovers the original data by XORing the scrambled input 
    //              with the generated key-stream. Output is gated by 'i_lane_vld'.
    // =========================================================================
    assign o_descrambled_data = i_lane_vld ? (i_scrambled_data ^ w_key_stream) : 8'h00;
    assign o_lane_vld_out     = i_lane_vld;

endmodule
