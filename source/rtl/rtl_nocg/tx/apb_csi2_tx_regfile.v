`timescale 1ns / 1ps

/*
===========================================================================
File Name   : apb_csi2_tx_regfile.v
Project     : MIPI CSI-2 Controller IP
===========================================================================

Description : APB Slave register file for MIPI CSI-2 TX
Standard    : AMBA APB Protocol Specification 

Registers:
	TX_CTRL @ 0x00
     [0]    TX_EN    : R/W  - Enables CSI-2 transmitter
     [1]    SW_RST   : R/W  - Software reset (self-clearing)
     [31:2] RSV      : RO   - Reserved, reads 0, writes ignored

	TX_CFG @ 0x04
     [0]    SCRAM_ENB: R/W  - Scramble Enable
     [1]    CRC_ENB  : R/W  - CRC Enable
     [31:2] RSV      : RO   - Reserved, reads 0, writes ignored
===========================================================================
*/

module apb_csi2_tx_regfile #(
    parameter integer APB_ADDR_WIDTH = 32
) (
    //----------------------------------------------------------------------
    // APB Clock and Reset
    //----------------------------------------------------------------------
    input  wire                      PCLK,       // APB clock
    input  wire                      PRESETn,    // APB reset, active-LOW

    //----------------------------------------------------------------------
    // APB Slave Interface
    //----------------------------------------------------------------------
    input  wire [APB_ADDR_WIDTH-1:0] PADDR,      // Byte address
    input  wire                      PSEL,       // Peripheral select
    input  wire                      PENABLE,    // ACCESS phase strobe
    input  wire                      PWRITE,     // 1=Write 0=Read
    input  wire [31:0]               PWDATA,     // Write data (32-bit bus)
    input  wire [3:0]                PSTRB,      // Write byte strobes

    output reg  [31:0]               PRDATA,     // Read data
    output wire                      PREADY,     // Slave ready (no wait states)
    output wire                      PSLVERR,    // Slave error

    //----------------------------------------------------------------------
    // Register outputs to CSI-2 TX Core
    //----------------------------------------------------------------------
    output reg                       tx_en,      // TX_CTRL[0] - TX Enable
    output reg                       sw_rst,     // TX_CTRL[1] - SW Reset pulse
    output reg                       scram_enb,  // TX_CFG[0]  - Scramble Enable
    output reg                       crc_enb     // TX_CFG[1]  - CRC Enable
);

    //----------------------------------------------------------------------
    // Local Parameters - Register Addresses
    //----------------------------------------------------------------------
    localparam [APB_ADDR_WIDTH-1:0] ADDR_TX_CTRL = 'h000;
    localparam [APB_ADDR_WIDTH-1:0] ADDR_TX_CFG  = 'h004;

    //----------------------------------------------------------------------
    // Internal Wires - APB Phase & Address Decode
    //----------------------------------------------------------------------
    wire wr_en;
    wire rd_en;
    wire sel_tx_ctrl;
    wire sel_tx_cfg;
    wire addr_valid;

    assign wr_en = PSEL & PENABLE &  PWRITE;
    assign rd_en = PSEL & PENABLE & ~PWRITE;

    assign sel_tx_ctrl = (PADDR[APB_ADDR_WIDTH-1:2] == ADDR_TX_CTRL[APB_ADDR_WIDTH-1:2]);
    assign sel_tx_cfg  = (PADDR[APB_ADDR_WIDTH-1:2] == ADDR_TX_CFG [APB_ADDR_WIDTH-1:2]);
    assign addr_valid  = sel_tx_ctrl | sel_tx_cfg;

    //----------------------------------------------------------------------
    // APB Response Signals
    //----------------------------------------------------------------------
    assign PREADY  = 1'b1;
    assign PSLVERR = PSEL & PENABLE & ~addr_valid;

    //----------------------------------------------------------------------
    // Register Write Logic
    //
    // Priority (highest to lowest):
    //   1. PRESETn LOW      - async reset clears all registers
    //   2. SW_RST self-clear - takes priority over APB write in same cycle
    //   3. APB write        - only fires when SW_RST is not self-clearing
    //----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_en     <= 1'b0;
            sw_rst    <= 1'b0;
            scram_enb <= 1'b0;
            crc_enb   <= 1'b0;

        end else if (sw_rst) begin
            sw_rst <= 1'b0;

        end else if (wr_en) begin
            //----------------------------------------------------------------
            // APB Write
            //----------------------------------------------------------------

            // TX_CTRL @ 0x000
            if (sel_tx_ctrl && PSTRB[0]) begin
                tx_en  <= PWDATA[0];    // [0] TX_EN
                sw_rst <= PWDATA[1];    // [1] SW_RST
                // [31:2] reserved
            end

            // TX_CFG @ 0x004
            if (sel_tx_cfg && PSTRB[0]) begin
                scram_enb <= PWDATA[0]; // [0] SCRAM_ENB
                crc_enb   <= PWDATA[1]; // [1] CRC_ENB
                // [31:2] reserved
            end

        end
    end

    //----------------------------------------------------------------------
    // APB Read
    //----------------------------------------------------------------------
    always @(*) begin
        PRDATA = 32'h0000_0000;

        if (rd_en) begin
            case (1'b1)
                sel_tx_ctrl : PRDATA = {{30{1'b0}}, sw_rst,   tx_en    };
                sel_tx_cfg  : PRDATA = {{30{1'b0}}, crc_enb,  scram_enb};
                default     : PRDATA = 32'h0000_0000;
            endcase
        end
    end

endmodule
