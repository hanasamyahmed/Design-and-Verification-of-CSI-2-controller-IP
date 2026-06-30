`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : I2C_csi_rx_reg_bank
// Description   : CSI-2 Receiver Register Bank (Control Plane)
//                 
//                 Implements memory-mapped configuration registers for the 
//                 CSI-2 Receiver subsystem. These registers are written and 
//                 read via the I2C-based Camera Control Interface (CCI).
//                 The output signals drive static configuration settings 
//                 downstream to the RX data-path and protocol logic.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : - Synchronous write, asynchronous active-low reset
//                 - Combinational read multiplexer
//                 - 8-bit data width, 16-bit address width
//                 - Address decoding using parameterized mappings
//-----------------------------------------------------------------------------

module I2C_csi_rx_reg_bank (
    // -- Clocks & Resets --
    input  wire        i_clk,             // System/CCI clock
    input  wire        i_rst_n,           // Active-low asynchronous reset

    // -- CCI (I2C) Register Access Interface --
    input  wire        i_reg_wr_en,       // Register write enable strobe
    input  wire        i_reg_rd_en,       // Register read enable strobe
    input  wire [15:0] i_reg_addr,        // 16-bit Register Address
    input  wire [7:0]  i_reg_wdata,       // 8-bit Write Data
    output reg  [7:0]  o_reg_rdata,       // 8-bit Read Data (Valid when i_reg_rd_en=1)

    // -- Configuration Outputs (To RX Control/Data Path) --
    output reg  [1:0]  o_virtual_channel, // Target Virtual Channel (VC) identifier
    output reg  [5:0]  o_data_type,       // Target Data Type (DT) code
    output reg  [1:0]  o_lane_count,      // Active MIPI D-PHY lane count (1, 2, or 4 lanes)
    output reg  [15:0] o_line_number,     // Expected line number/frame height
    output reg  [15:0] o_word_count       // Expected word count/line length payload
);

    //=========================================================================
    // REGISTER ADDRESS MAP (Local Parameters)
    //=========================================================================
    // Using parameters prevents magic numbers and makes address maps easier 
    // to maintain and cross-reference with the software team's headers.
    localparam [15:0]
        ADDR_VC_DT       = 16'h0000,      // [7:6] Virtual Channel, [5:0] Data Type
        ADDR_LANE_CNT    = 16'h0001,      // [1:0] Active Lane Count
        ADDR_LINE_NUM_HI = 16'h0002,      // [7:0] Line Number MSB
        ADDR_LINE_NUM_LO = 16'h0003,      // [7:0] Line Number LSB
        ADDR_WORD_CNT_HI = 16'h0004,      // [7:0] Word Count MSB
        ADDR_WORD_CNT_LO = 16'h0005;      // [7:0] Word Count LSB

    //=========================================================================
    // WRITE OPERATION (Sequential)
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // Reset to safe/standard defaults 
            o_virtual_channel <= 2'b00;
            o_data_type       <= 6'h2A;   // Default DT = 0x2A (typically RAW8)
            o_lane_count      <= 2'b01;   // Default 1 lane active
            o_line_number     <= 16'h0000;
            o_word_count      <= 16'h0000;
        end 
        else if (i_reg_wr_en) begin
            // Decode address and latch write data into appropriate configuration registers
            case (i_reg_addr)
                ADDR_VC_DT:       {o_virtual_channel, o_data_type} <= {i_reg_wdata[7:6], i_reg_wdata[5:0]};
                ADDR_LANE_CNT:    o_lane_count                     <= i_reg_wdata[1:0];
                ADDR_LINE_NUM_HI: o_line_number[15:8]              <= i_reg_wdata;
                ADDR_LINE_NUM_LO: o_line_number[7:0]               <= i_reg_wdata;
                ADDR_WORD_CNT_HI: o_word_count[15:8]               <= i_reg_wdata;
                ADDR_WORD_CNT_LO: o_word_count[7:0]                <= i_reg_wdata;
                
                default: ; // Do nothing for unmapped addresses to preserve current state
            endcase
        end
    end

    //=========================================================================
    // READ OPERATION (Combinational Multiplexer)
    //=========================================================================
    always @(*) begin
        // Default assignment to prevent latches and ensure the bus is driven 
        // to a known state (0x00) when a read is not explicitly requested.
        o_reg_rdata = 8'h00;

        if (i_reg_rd_en) begin
            case (i_reg_addr)
                ADDR_VC_DT:       o_reg_rdata = {o_virtual_channel, o_data_type};
                ADDR_LANE_CNT:    o_reg_rdata = {6'd0, o_lane_count}; // Zero-pad the upper 6 bits
                ADDR_LINE_NUM_HI: o_reg_rdata = o_line_number[15:8];
                ADDR_LINE_NUM_LO: o_reg_rdata = o_line_number[7:0];
                ADDR_WORD_CNT_HI: o_reg_rdata = o_word_count[15:8];
                ADDR_WORD_CNT_LO: o_reg_rdata = o_word_count[7:0];
                
                default:          o_reg_rdata = 8'h00; // Unmapped reads gracefully return 0x00
            endcase
        end
    end

endmodule
