`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : I2C_top_cci_csi_rx
// Description   : Top-Level CSI-2 Receiver Control and Configuration Interface
//                 
//                 This module integrates the I2C Slave (CCI) interface, the 
//                 memory-mapped Configuration Register Bank, and the high-level 
//                 RX state machine. It serves as the primary control plane 
//                 bridge between the host processor and the CSI-2 RX data path.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : Structural Top-Level Integration
//                 - Instantiates: i2c_slave_with_registers_rx
//                 - Instantiates: I2C_csi_rx_reg_bank
//                 - Instantiates: I2C_csi_rx_fsm
//-----------------------------------------------------------------------------

module I2C_top_cci_csi_rx (
    // -- Clocks & Resets --
    input  wire        i_clk,             // System Clock
    input  wire        i_rst_n,           // Active-low asynchronous reset

    // -- I2C (CCI) Bus Interface --
    input  wire        i_SCL,             // I2C Serial Clock
    inout  wire        io_sda,            // I2C Serial Data (Bidirectional)

    // -- RX Datapath Control Inputs --
    input  wire        i_packet_start,    // Triggered on SoT (Start of Transmission)
    input  wire        i_packet_end,      // Triggered on EoT (End of Transmission)

    // -- RX Configuration & Status Outputs --
    output wire [1:0]  o_virtual_channel, // Configured Target Virtual Channel
    output wire [5:0]  o_data_type,       // Configured Target Data Type
    output wire [1:0]  o_lane_count,      // Configured Active Lane Count
    output wire [15:0] o_line_number,     // Configured Frame Height (Lines)
    output wire [15:0] o_word_count,      // Configured Payload Length (Bytes/Line)
    output wire        o_rx_active        // FSM Status: Active reception window
);

    //=========================================================================
    // INTERNAL INTERCONNECT WIRES
    //=========================================================================
    // These wires bridge the generic I2C slave interface to the Register Bank
    wire        w_reg_wr_en;
    wire        w_reg_rd_en;
    wire [15:0] w_reg_addr;
    wire [7:0]  w_reg_wdata;
    wire [7:0]  w_reg_rdata;

    //=========================================================================
    // MODULE INSTANTIATIONS
    //=========================================================================

    //-------------------------------------------------------------------------
    // 1. I2C Slave Interface (CCI Physical/Link Layer)
    //-------------------------------------------------------------------------
    i2c_slave_with_registers_rx u_i2c_slave (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_SCL       (i_SCL),
        .io_sda      (io_sda),
        
        // Register bus interface
        .o_reg_wr_en (w_reg_wr_en),
        .o_reg_rd_en (w_reg_rd_en),
        .o_reg_addr  (w_reg_addr),
        .o_reg_wdata (w_reg_wdata),
        .i_reg_rdata (w_reg_rdata)
    );

    //-------------------------------------------------------------------------
    // 2. CSI-2 RX Register Bank (Control Plane)
    //-------------------------------------------------------------------------
    I2C_csi_rx_reg_bank u_reg_bank (
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),
        
        // Register bus interface
        .i_reg_wr_en       (w_reg_wr_en),
        .i_reg_rd_en       (w_reg_rd_en),
        .i_reg_addr        (w_reg_addr),
        .i_reg_wdata       (w_reg_wdata),
        .o_reg_rdata       (w_reg_rdata),
        
        // Configuration Outputs
        .o_virtual_channel (o_virtual_channel),
        .o_data_type       (o_data_type),
        .o_lane_count      (o_lane_count),
        .o_line_number     (o_line_number),
        .o_word_count      (o_word_count)
    );

    //-------------------------------------------------------------------------
    // 3. CSI-2 RX Finite State Machine (Status Monitor)
    //-------------------------------------------------------------------------
    I2C_csi_rx_fsm u_rx_fsm (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        
        // Control triggers
        .i_packet_start (i_packet_start),
        .i_packet_end   (i_packet_end),
        
        // Status output
        .o_rx_active    (o_rx_active)
    );

endmodule
