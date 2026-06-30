`timescale 1ns / 1ps

/*
===========================================================================
File Name   : apb_csi2_rx_regfile.v
Project     : MIPI CSI-2 Controller IP
===========================================================================

Description : APB Slave register file for MIPI CSI-2 RX
Standard    : AMBA APB Protocol Specification 

Registers:
	RX_CTRL @ 0x00
     [0]    RX_EN    : R/W  - Enables CSI-2 receiver
     [1]    SW_RST   : R/W  - Software reset (self-clearing)
     [31:2] RSV      : RO   - Reserved, reads 0, writes ignored

	RX_CFG @ 0x04
     [0]    SCRAM_ENB: R/W  - Scramble Enable
     [1]    CRC_ENB  : R/W  - CRC Enable
     [31:2] RSV      : RO   - Reserved, reads 0, writes ignored
	 
	RX_ERR @ 0x0C
	 [0]    CRC_ERR  : RO   - Payload CRC error (sticky)
     [1]    ECC_ERR  : RO   - Header ECC error (sticky)
	 [2]    CECC_ERR : RO   - Corrected ECC error (sticky)
     [31:3] RSV      : RO   - Reserved, reads 0, writes ignored	
	 
===========================================================================
*/

module apb_csi2_rx_regfile #(
    parameter integer APB_ADDR_WIDTH = 32
) (
    //--------------------------------------------------------------------------
    // APB Clock and Reset
    //--------------------------------------------------------------------------
    input  wire                      PCLK,           // APB clock (rising-edge)
    input  wire                      PRESETn,        // APB reset, active-LOW

    //--------------------------------------------------------------------------
    // APB Slave Interface
    //--------------------------------------------------------------------------
    input  wire [APB_ADDR_WIDTH-1:0] PADDR,          // Byte address
    input  wire                      PSEL,           // Peripheral select
    input  wire                      PENABLE,        // ACCESS phase strobe
    input  wire                      PWRITE,         // 1=Write  0=Read
    input  wire [31:0]               PWDATA,         // Write data
    input  wire [3:0]                PSTRB,          // Write byte strobes

    output reg  [31:0]               PRDATA,         // Read data
    output wire                      PREADY,         // Slave ready 
    output wire                      PSLVERR,        // Slave error

    //--------------------------------------------------------------------------
    // Register outputs to CSI-2 RX 
    //--------------------------------------------------------------------------
    output reg                       rx_en,          // RX_CTRL[0] - RX Enable
    output reg                       sw_rst,         // RX_CTRL[1] - SW Reset pulse
    output reg                       rx_scram_enb,   // RX_CFG[0]  - Scramble Enable
    output reg                       rx_crc_enb,     // RX_CFG[1]  - CRC Enable

    //--------------------------------------------------------------------------
    // error inputs from CSI-2 RX 
    //--------------------------------------------------------------------------
    input  wire                      hw_crc_err,     // RX_ERR[0] - CRC error 
    input  wire                      hw_ecc_err,     // RX_ERR[1] - ECC error 
    input  wire                      hw_cecc_err     // RX_ERR[2] - Corrected ECC 
);

    //--------------------------------------------------------------------------
    // Local Parameters - Register Addresses 
    //--------------------------------------------------------------------------
    localparam [APB_ADDR_WIDTH-1:0] ADDR_RX_CTRL = 'h000;
    localparam [APB_ADDR_WIDTH-1:0] ADDR_RX_CFG  = 'h004;
    localparam [APB_ADDR_WIDTH-1:0] ADDR_RX_ERR  = 'h00C;

    //--------------------------------------------------------------------------
    // Internal Wires
    //--------------------------------------------------------------------------
    wire wr_en;
    wire rd_en;
    wire sel_rx_ctrl;
    wire sel_rx_cfg;
    wire sel_rx_err;
    wire addr_valid;

    assign wr_en = PSEL & PENABLE &  PWRITE;
    assign rd_en = PSEL & PENABLE & ~PWRITE;

    assign sel_rx_ctrl = (PADDR[APB_ADDR_WIDTH-1:2] == ADDR_RX_CTRL[APB_ADDR_WIDTH-1:2]);
    assign sel_rx_cfg  = (PADDR[APB_ADDR_WIDTH-1:2] == ADDR_RX_CFG [APB_ADDR_WIDTH-1:2]);
    assign sel_rx_err  = (PADDR[APB_ADDR_WIDTH-1:2] == ADDR_RX_ERR [APB_ADDR_WIDTH-1:2]);
    assign addr_valid  = sel_rx_ctrl | sel_rx_cfg | sel_rx_err;

    //--------------------------------------------------------------------------
    // APB Response Signals
    //--------------------------------------------------------------------------
    assign PREADY  = 1'b1;
    assign PSLVERR = PSEL & PENABLE & ~addr_valid;

    //--------------------------------------------------------------------------
    // Sticky error registers
    //--------------------------------------------------------------------------
    reg crc_err_sticky;
    reg ecc_err_sticky;
    reg cecc_err_sticky;

    //--------------------------------------------------------------------------
    // R/W Register Write Logic
    //
    // Priority (highest to lowest):
    //   1. PRESETn LOW       - async reset clears all R/W registers
    //   2. SW_RST self-clear - takes priority over APB write in the same cycle
    //   3. APB write         - only fires when SW_RST is not self-clearing
    //--------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_en        <= 1'b0;
            sw_rst       <= 1'b0;
            rx_scram_enb <= 1'b0;
            rx_crc_enb   <= 1'b0;

        end else if (sw_rst) begin
            //------------------------------------------------------------------
            // SW_RST self-clear: highest priority after reset.
            //------------------------------------------------------------------
            sw_rst <= 1'b0;

        end else if (wr_en) begin
            //------------------------------------------------------------------
            // APB Write: only reached when sw_rst is not self-clearing.
            //------------------------------------------------------------------

            // RX_CTRL @ 0x000
            if (sel_rx_ctrl && PSTRB[0]) begin
                rx_en  <= PWDATA[0];    // [0] RX_EN
                sw_rst <= PWDATA[1];    // [1] SW_RST
                // [31:2] reserved
            end

            // RX_CFG @ 0x004
            if (sel_rx_cfg && PSTRB[0]) begin
                rx_scram_enb <= PWDATA[0]; // [0] RX_SCRAM_ENB
                rx_crc_enb   <= PWDATA[1]; // [1] RX_CRC_ENB
                // [31:2] reserved
            end

        end
    end

    //--------------------------------------------------------------------------
    // RX_ERR Sticky Bit Logic
    //--------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            crc_err_sticky  <= 1'b0;
            ecc_err_sticky  <= 1'b0;
            cecc_err_sticky <= 1'b0;
        end else begin
            if (hw_crc_err)  crc_err_sticky  <= 1'b1;
            if (hw_ecc_err)  ecc_err_sticky  <= 1'b1;
            if (hw_cecc_err) cecc_err_sticky <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Register Read Logic
    //--------------------------------------------------------------------------
    always @(*) begin
        PRDATA = 32'h0000_0000;

        if (rd_en) begin
            case (1'b1)
                sel_rx_ctrl : PRDATA = {{30{1'b0}}, sw_rst,          rx_en        };
                sel_rx_cfg  : PRDATA = {{30{1'b0}}, rx_crc_enb,      rx_scram_enb };
                sel_rx_err  : PRDATA = {{29{1'b0}}, cecc_err_sticky,
                                                    ecc_err_sticky,
                                                    crc_err_sticky              };
                default     : PRDATA = 32'h0000_0000;
            endcase
        end
    end

endmodule
