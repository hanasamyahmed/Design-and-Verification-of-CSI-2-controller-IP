`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : I2C_csi_rx_fsm
// Description   : CSI-2 Receiver Finite State Machine (RX FSM)
//                 
//                 Manages the high-level packet reception states for the 
//                 CSI-2 protocol. Monitors Start of Transmission (SoT) and 
//                 End of Transmission (EoT) markers to generate an active 
//                 reception window (o_rx_active) for downstream payload 
//                 processing modules.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : 3-State FSM (IDLE, RECEIVE, END_PKT)
//                 - Asynchronous active-low reset
//                 - Explicit state encoding
//                 - Registered outputs for glitch-free downstream assertion
//-----------------------------------------------------------------------------

module I2C_csi_rx_fsm (
    // -- Clocks & Resets --
    input  wire i_clk,          // High-speed system or byte clock
    input  wire i_rst_n,        // Active-low asynchronous reset

    // -- Control Inputs (From PHY/Sync Logic) --
    input  wire i_packet_start, // Triggered on Start of Packet detection
    input  wire i_packet_end,   // Triggered on End of Packet detection

    // -- Status Outputs (To Downstream Logic) --
    output reg  o_rx_active     // Asserts HIGH while payload is actively being received
);

    //=========================================================================
    // STATE ENCODING (Local Parameters)
    //=========================================================================
    localparam [1:0] 
        IDLE    = 2'b00,        // Waiting for packet start trigger
        RECEIVE = 2'b01,        // Actively receiving packet payload
        END_PKT = 2'b10;        // Packet complete, single-cycle cleanup state

    //=========================================================================
    // INTERNAL SIGNALS
    //=========================================================================
    reg [1:0] state;            // Current FSM state register
    reg [1:0] next_state;       // Combinational next state evaluation

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
                if (i_packet_start) begin
                    next_state = RECEIVE;
                end
            end

            RECEIVE: begin
                if (i_packet_end) begin
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
    // combinational glitches on the o_rx_active signal.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_rx_active <= 1'b0;
        end 
        else begin
            // Output goes HIGH 1 cycle after entering RECEIVE state
            o_rx_active <= (state == RECEIVE);
        end
    end

endmodule
