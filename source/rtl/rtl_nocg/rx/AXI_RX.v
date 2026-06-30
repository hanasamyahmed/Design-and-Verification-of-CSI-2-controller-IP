// =============================================================================
// Module Name : axi_stream_bridge
// File Name   : axi_stream_bridge.v
// Author      : Hana Samy 
// Date        : June 2026
// Description : Combinational protocol bridge translating a custom pixel streaming 
//               interface to an AXI4-Stream Master interface. Adapts 24-bit RGB 
//               data to a word-aligned 32-bit AXI bus by zero-padding the upper 
//               bits, and maps sideband signals (SOF/EOL) directly to TUSER/TLAST.
// =============================================================================

`timescale 1ns / 1ps

module axi_stream_bridge #(
    parameter P_PIX_WIDTH = 24, // Input Pixel Width (e.g., RGB888)
    parameter P_AXI_WIDTH = 32  // Output AXI Width (Word Aligned)
)(
    // =========================================================================
    // System Signals
    // =========================================================================
    // spyglass disable_block W240
    // Waive W240: Clock and reset are required for AXI interface compliance 
    // but are intentionally unused in this purely combinational bridge.
    input  wire                         i_aclk,
    input  wire                         i_aresetn,
    // spyglass enable_block W240

    // =========================================================================
    // Input Interface (From Asynchronous FIFO)
    // =========================================================================
    input  wire [P_PIX_WIDTH-1:0]       i_pix_data,
    input  wire                         i_pix_last,  // End of Line (EOL)
    input  wire                         i_pix_user,  // Start of Frame (SOF)
    input  wire                         i_pix_valid, // Data Valid
    output wire                         o_pix_ready, // Backpressure to FIFO

    // =========================================================================
    // AXI4-Stream Master Output (To System Interconnect)
    // =========================================================================
    output wire [P_AXI_WIDTH-1:0]       m_axis_tdata,
    output wire [(P_AXI_WIDTH/8)-1:0]   m_axis_tkeep, // Byte Qualifiers
    output wire                         m_axis_tlast, // Packet Boundary
    output wire                         m_axis_tuser, // User Sideband Signal (SOF)
    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready
);

    // =========================================================================
    // 1. Data Width Adaptation (Padding)
    // =========================================================================
    // Maps 24-bit input data to the lower 24 bits of the 32-bit AXI stream.
    // Pads the upper 8 bits with leading zeros.
    // Concatenation Syntax: { {Repeat_Count{Value}}, Signal }
    assign m_axis_tdata = { {(P_AXI_WIDTH - P_PIX_WIDTH){1'b0}}, i_pix_data };

    // =========================================================================
    // 2. Protocol Handshake (Transparent Bridge)
    // =========================================================================
    // Passthrough logic: The bridge contains no registers and acts as a direct 
    // combinational pipeline connecting the FIFO to the AXI interconnect.
    assign m_axis_tvalid = i_pix_valid;   // Forward Valid downstream
    assign o_pix_ready   = m_axis_tready; // Forward Ready (backpressure) upstream to FIFO

    // =========================================================================
    // 3. Sideband Signals Mapping
    // =========================================================================
    
    // TLAST: Indicates End of Line (EOL) packet boundary
    assign m_axis_tlast = i_pix_last;

    // TUSER: Indicates Start of Frame (SOF) sideband marker
    assign m_axis_tuser = i_pix_user;

    // TKEEP: Byte Keep Strobe
    // Indicates active/valid byte lanes in the 32-bit word.
    // Driven high across all lanes, treating padding as valid filler payload.
    assign m_axis_tkeep = {(P_AXI_WIDTH/8){1'b1}}; 

endmodule