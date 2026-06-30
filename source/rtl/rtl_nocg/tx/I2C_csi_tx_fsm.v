`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : I2C_csi_tx_fsm
// Description   : CSI-2 Transmitter Finite State Machine (TX FSM)
//                 
//                 Controls the high-level packet transmission states for the 
//                 CSI-2 protocol. Monitors packet validity and end-of-packet 
//                 markers to generate an active transmission window 
//                 (o_tx_active) for upstream payload generation modules.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : 3-State FSM (IDLE, TRANSMIT, END_PKT)
//                 - Asynchronous active-low reset
//                 - Explicit state encoding
//                 - Registered outputs for glitch-free upstream assertion
//-----------------------------------------------------------------------------

module I2C_csi_tx_fsm (
    // -- Clocks & Resets --
    input  wire i_clk,           // High-speed system or byte clock
    input  wire i_rst_n,         // Active-low asynchronous reset

    // -- Control Inputs (From Packetizer/Data Path) --
    input  wire i_packet_valid,  // Triggered when a valid packet is ready to transmit
    input  wire i_end_of_packet, // Triggered when the last byte of the packet is sent

    // -- Status Outputs (To Upstream/Control Logic) --
    output reg  o_tx_active      // Asserts HIGH while payload is actively being transmitted
);

    //=========================================================================
    // STATE ENCODING (Local Parameters)
    //=========================================================================
    localparam [1:0] 
        IDLE     = 2'b00,        // Waiting for packet valid trigger
        TRANSMIT = 2'b01,        // Actively transmitting packet payload
        END_PKT  = 2'b10;        // Packet complete, single-cycle cleanup state

    //=========================================================================
    // INTERNAL SIGNALS
    //=========================================================================
    reg [1:0] state;             // Current FSM state register
    reg [1:0] next_state;        // Combinational next state evaluation

    //=========================================================================
    // FSM SEQUENTIAL LOGIC (State Register)
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= IDLE;
        end 
        else begin
            state <= next_state;
        end
    end

    //=========================================================================
    // FSM COMBINATIONAL LOGIC (Next State Decoder)
    //=========================================================================
    always @(*) begin
        // Default assignment to prevent inferring latches during synthesis
        next_state = state;

        case (state)
            IDLE: begin
                if (i_packet_valid) begin
                    next_state = TRANSMIT;
                end
            end

            TRANSMIT: begin
                if (i_end_of_packet) begin
                    next_state = END_PKT;
                end
            end

            END_PKT: begin
                // Unconditional transition back to IDLE after one clock cycle
                next_state = IDLE;
            end

            default: begin
                // Fault tolerance: return to IDLE if an undefined state is entered
                next_state = IDLE;
            end
        endcase
    end

    //=========================================================================
    // OUTPUT LOGIC (Registered)
    //=========================================================================
    // Utilizing registered outputs ensures timing safety and prevents 
    // combinational glitches on the o_tx_active signal.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_tx_active <= 1'b0;
        end 
        else begin
            // Output goes HIGH 1 cycle after entering TRANSMIT state
            o_tx_active <= (state == TRANSMIT);
        end
    end

endmodule
