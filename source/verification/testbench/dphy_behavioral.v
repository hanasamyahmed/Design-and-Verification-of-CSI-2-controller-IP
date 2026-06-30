`timescale 1ns / 1ps

// ============================================================================
// File Name   : dphy_behavioral.v
// Author      : Abdelrahman Elsayed
// Project     : MIPI CSI Controller IP
// Description : Behavioral Model of MIPI D-PHY.
//               Acts as a high-level loopback model for functional simulation.
//               Simulates:
//               - Analog wake-up times (Clock Lane Handshake).
//               - Data Lane ready/request Handshaking.
//               - High-Speed (HS) data loopback from TX to RX PPI.
//               - Low-Power (LP) and Ultra-Low Power Mode (ULPM) status signals.
// ============================================================================

module dphy_behavioral #(
    // Parameter to control the simulated analog PLL lock/wake-up time
    parameter PLL_LOCK_DELAY = 15
)(
    input  wire        i_clk_pll,        // Free-running clock internal to DPHY
    input  wire        i_rst_n,
    
    // -------------------------------------------------------------------------
    // Interfaces from/to TX PPI (High-Speed)
    // ---------------------------------------------------------
    input  wire        i_TxClkRequestHS,
    output reg         o_TxClkReadyHS,
    output wire        o_TxByteClkHS,
    
    input  wire [3:0]  i_TxRequestHS,
    output reg  [3:0]  o_TxReadyHS,
    
    input  wire [7:0]  i_TxDataHS_0, i_TxDataHS_1, i_TxDataHS_2, i_TxDataHS_3,
    input  wire        i_TxValidHS_0, i_TxValidHS_1, i_TxValidHS_2, i_TxValidHS_3,

    // -------------------------------------------------------------------------
    // Interfaces from/to TX PPI (LP & Control)
    // ---------------------------------------------------------
    input  wire        i_TxUlpmClk,
    input  wire [3:0]  i_TxRequestEsc,
    input  wire [3:0]  i_TxUlpmEsc,

    // -------------------------------------------------------------------------
    // Interfaces from/to RX PPI (High-Speed)
    // ---------------------------------------------------------
    output wire        o_RxByteClkHS,
    
    output wire [7:0]  o_RxDataHS_0, o_RxDataHS_1, o_RxDataHS_2, o_RxDataHS_3,
    output wire        o_RxValidHS_0, o_RxValidHS_1, o_RxValidHS_2, o_RxValidHS_3,
    output wire        o_RxActiveHS_0, o_RxActiveHS_1, o_RxActiveHS_2, o_RxActiveHS_3,
    output wire        o_RxSyncHS_0, o_RxSyncHS_1, o_RxSyncHS_2, o_RxSyncHS_3,

    // -------------------------------------------------------------------------
    // Interfaces from/to RX PPI (LP & Control)
    // ---------------------------------------------------------
    output wire        o_Stopstate_0, o_Stopstate_1, o_Stopstate_2, o_Stopstate_3,
    output wire        o_RxUlpmEsc_0, o_RxUlpmEsc_1, o_RxUlpmEsc_2, o_RxUlpmEsc_3,

    // -------------------------------------------------------------------------
    // Interfaces from/to RX PPI (Errors - Fixed to 0 for ideal sim)
    // ---------------------------------------------------------
    output wire        o_ErrSotHS_0, o_ErrSotHS_1, o_ErrSotHS_2, o_ErrSotHS_3,
    output wire        o_ErrSotSyncHS_0, o_ErrSotSyncHS_1, o_ErrSotSyncHS_2, o_ErrSotSyncHS_3,
    output wire        o_ErrControl_0, o_ErrControl_1, o_ErrControl_2, o_ErrControl_3,
    output wire        o_ErrEsc_0, o_ErrEsc_1, o_ErrEsc_2, o_ErrEsc_3
);

    // =========================================================================
    // 1. Clock Lane Handshake
    // Description: Simulates the analog wake-up time of the D-PHY clock lane.
    //              Uses parameterized delay to mimic PLL lock/stabilization.
    // =========================================================================
    always @(posedge i_clk_pll or negedge i_rst_n) begin
        if (!i_rst_n) o_TxClkReadyHS <= 1'b0;
        else          o_TxClkReadyHS <= #(PLL_LOCK_DELAY) i_TxClkRequestHS; 
    end

    // Clock gating: Byte clock is only available when the D-PHY is ready
    assign o_TxByteClkHS = o_TxClkReadyHS ? i_clk_pll : 1'b0;
    assign o_RxByteClkHS = o_TxByteClkHS; 

    // =========================================================================
    // 2. Data Lane Handshake & Delay
    // Description: Simple propagation of data lane requests to ready signals.
    // =========================================================================
    always @(posedge o_TxByteClkHS or negedge i_rst_n) begin
        if (!i_rst_n) o_TxReadyHS <= 4'd0;
        else          o_TxReadyHS <= i_TxRequestHS; 
    end

    // =========================================================================
    // 3. HS Data Transmission Loopback
    // Description: Connects TX HS data paths directly to RX HS data paths 
    //              to facilitate end-to-end digital controller verification.
    // =========================================================================
    assign o_RxActiveHS_0 = i_TxRequestHS[0];
    assign o_RxValidHS_0  = i_TxValidHS_0;
    assign o_RxDataHS_0   = i_TxValidHS_0 ? i_TxDataHS_0 : 8'h00; 
    assign o_RxSyncHS_0   = i_TxValidHS_0; 

    assign o_RxActiveHS_1 = i_TxRequestHS[1];
    assign o_RxValidHS_1  = i_TxValidHS_1;
    assign o_RxDataHS_1   = i_TxValidHS_1 ? i_TxDataHS_1 : 8'h00;
    assign o_RxSyncHS_1   = i_TxValidHS_1;

    assign o_RxActiveHS_2 = i_TxRequestHS[2];
    assign o_RxValidHS_2  = i_TxValidHS_2;
    assign o_RxDataHS_2   = i_TxValidHS_2 ? i_TxDataHS_2 : 8'h00;
    assign o_RxSyncHS_2   = i_TxValidHS_2;

    assign o_RxActiveHS_3 = i_TxRequestHS[3];
    assign o_RxValidHS_3  = i_TxValidHS_3;
    assign o_RxDataHS_3   = i_TxValidHS_3 ? i_TxDataHS_3 : 8'h00;
    assign o_RxSyncHS_3   = i_TxValidHS_3;

    // =========================================================================
    // 4. Low-Power (LP) & Control Loopback
    // Description: Manages PPI status signals like Stopstate and ULPM.
    //              Stopstate is active when no High-Speed request is present.
    // =========================================================================
    assign o_Stopstate_0 = ~i_TxRequestHS[0];
    assign o_Stopstate_1 = ~i_TxRequestHS[1];
    assign o_Stopstate_2 = ~i_TxRequestHS[2];
    assign o_Stopstate_3 = ~i_TxRequestHS[3];

    // Loopback ULPM Escape status from TX to RX
    assign o_RxUlpmEsc_0 = i_TxUlpmEsc[0];
    assign o_RxUlpmEsc_1 = i_TxUlpmEsc[1];
    assign o_RxUlpmEsc_2 = i_TxUlpmEsc[2];
    assign o_RxUlpmEsc_3 = i_TxUlpmEsc[3];

    // =========================================================================
    // 5. Error Signals
    // Description: Permanently tied to 0 to simulate an ideal transmission 
    //              medium during standard functional verification.
    // =========================================================================
    assign o_ErrSotHS_0 = 0; assign o_ErrSotHS_1 = 0; assign o_ErrSotHS_2 = 0; assign o_ErrSotHS_3 = 0;
    assign o_ErrSotSyncHS_0 = 0; assign o_ErrSotSyncHS_1 = 0; assign o_ErrSotSyncHS_2 = 0; assign o_ErrSotSyncHS_3 = 0;
    assign o_ErrControl_0 = 0; assign o_ErrControl_1 = 0; assign o_ErrControl_2 = 0; assign o_ErrControl_3 = 0;
    assign o_ErrEsc_0 = 0; assign o_ErrEsc_1 = 0; assign o_ErrEsc_2 = 0; assign o_ErrEsc_3 = 0;

endmodule
