// =============================================================================
// File        : csi_tb_top.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : Top module for CSI-2 Environment.
// =============================================================================
`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

import csi_seq_item_pkg::*;
import csi_config_pkg::*;
import csi_tx_sequencer_pkg::*;
import csi_tx_driver_pkg::*;
import csi_tx_monitor_pkg::*;
import csi_rx_monitor_pkg::*;
import csi_tx_agent_pkg::*;
import csi_rx_agent_pkg::*;
import csi_scoreboard_pkg::*;
import csi_coverage_pkg::*;
import csi_top_env_pkg::*;
import csi_frame_sequence_pkg::*;
import csi_system_test_pkg::*;

module csi_tb_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int NUM_PIXELS = 1000;
    localparam int NUM_LINES  = 100;
    localparam int NUM_FRAMES = 10;

    // =========================================================================
    // Fixed-period clocks
    // FIX: pixel_clk must be 40 MHz (#12.5 half-period), NOT 20 MHz (#25).
    //      The reference TB uses `always #12.5 pixel_clk = ~pixel_clk`.
    //      At 20 MHz the AXI-S pixel data arrived at half the rate the
    //      packetizer expected relative to byte_clk, corrupting packet headers
    //      and causing ECC double-bit errors on every frame.
    // =========================================================================
    logic pclk      = 0;  always #10.00 pclk      = ~pclk;      // 50  MHz
    logic pixel_clk = 0;  always #12.5  pixel_clk = ~pixel_clk; // 40  MHz  ← FIXED
    logic byte_clk  = 0;  always #12.5  byte_clk  = ~byte_clk;  // 40  MHz

    // =========================================================================
    // cfg_active_lanes – plain logic initialised to 4 lanes so that
    // phy_half_period / sys_half_period are valid at time 0.
    // Updated by always_ff from the interface sideband signals.
    // =========================================================================
    logic [2:0]  cfg_active_lanes = 3'd4;
    logic [15:0] cfg_frame_lines  = NUM_LINES;
    logic [5:0]  cfg_rx_data_type = 6'h2A;

    // Variable-period clocks driven by cfg_active_lanes
    real sys_half_period = 3.125;
    always @(*) begin
        if      (cfg_active_lanes == 3'd4) sys_half_period = 6.25  / 2.0;  // 160 MHz
        else if (cfg_active_lanes == 3'd2) sys_half_period = 12.50 / 2.0;  //  80 MHz
        else                               sys_half_period = 25.00 / 2.0;  //  40 MHz
    end
    logic sys_clk = 0;
    always #sys_half_period sys_clk = ~sys_clk;

    real phy_half_period = 3.125;
    always @(*) begin
        if      (cfg_active_lanes == 3'd4) phy_half_period = 3.125;
        else if (cfg_active_lanes == 3'd2) phy_half_period = 6.250;
        else                               phy_half_period = 12.50;
    end
    logic clk_phy_pll = 0;
    always #phy_half_period clk_phy_pll = ~clk_phy_pll;

    // =========================================================================
    // Module-level resets
    // FIX: These are driven by always_comb from the interface drv_* signals
    // for hard-reset capability, BUT reinit() in the corrected driver now only
    // does APB soft-reset (matching reference TB), so drv_* stay high after
    // the initial reset and these wires are stable during normal operation.
    // =========================================================================
    logic sys_rst_n;
    logic preset_n;
    logic pixel_rst_n;
    logic byte_rst_n;

    // =========================================================================
    // I2C open-drain bus
    // =========================================================================
    wire i2c_scl_drv;
    wire i2c_sda_drv;
    wire i2c_sda_bus;

    // =========================================================================
    // DUT output wires
    // =========================================================================
    wire         tx_axis_tready;
    wire  [31:0] tx_apb_prdata;
    wire         tx_apb_pready;
    wire  [31:0] rx_axis_tdata;
    wire  [3:0]  rx_axis_tkeep;
    wire         rx_axis_tlast;
    wire         rx_axis_tuser;
    wire         rx_axis_tvalid;
    wire  [31:0] rx_apb_prdata;
    wire         rx_apb_pready;
    wire [7:0]   tx_lane0_data_out, tx_lane1_data_out;
    wire [7:0]   tx_lane2_data_out, tx_lane3_data_out;
    wire         tx_lane0_vld_out,  tx_lane1_vld_out;
    wire         tx_lane2_vld_out,  tx_lane3_vld_out;
    wire         tx_req_hs_out;
    wire [7:0]   dig_tx_pkt_data_in;
    wire         dig_tx_pkt_vld_in;
    wire         ppi_tx_ClkRequestHS, ppi_tx_ClkReadyHS, ppi_tx_ByteClkHS;
    wire [3:0]   ppi_tx_RequestHS,  ppi_tx_ReadyHS;
    wire [7:0]   ppi_tx_DataHS_0,   ppi_tx_DataHS_1;
    wire [7:0]   ppi_tx_DataHS_2,   ppi_tx_DataHS_3;
    wire         ppi_tx_ValidHS_0,  ppi_tx_ValidHS_1;
    wire         ppi_tx_ValidHS_2,  ppi_tx_ValidHS_3;
    wire         ppi_rx_ByteClkHS;
    wire [7:0]   ppi_rx_DataHS_0,   ppi_rx_DataHS_1;
    wire [7:0]   ppi_rx_DataHS_2,   ppi_rx_DataHS_3;
    wire         ppi_rx_ValidHS_0,  ppi_rx_ValidHS_1;
    wire         ppi_rx_ValidHS_2,  ppi_rx_ValidHS_3;
    wire         ppi_rx_ActiveHS_0, ppi_rx_ActiveHS_1;
    wire         ppi_rx_ActiveHS_2, ppi_rx_ActiveHS_3;
    wire         ppi_rx_SyncHS_0,   ppi_rx_SyncHS_1;
    wire         ppi_rx_SyncHS_2,   ppi_rx_SyncHS_3;
    wire         rx_crc_ok, rx_crc_done, rx_ecc_single, rx_ecc_double;

    // =========================================================================
    // Interface instantiation
    // =========================================================================
    csi_tx_if tx_if (
        .pixel_clk(pixel_clk), .pclk(pclk),
        .byte_clk(byte_clk),   .sys_clk(sys_clk)
    );

    csi_rx_if rx_if (
        .pixel_clk(pixel_clk), .pclk(pclk),
        .byte_clk(byte_clk),   .sys_clk(sys_clk)
    );

    // =========================================================================
    // Wire drv_* interface signals to module-level resets via always_comb.
    // After the corrected reinit() (APB soft-reset only), drv_* remain 1
    // throughout normal operation.  This wiring is kept so the initial reset
    // sequence and any emergency hard-reset path still work correctly.
    // =========================================================================
    always_comb begin
        sys_rst_n   = tx_if.drv_sys_rst_n;
        preset_n    = tx_if.drv_preset_n;
        pixel_rst_n = tx_if.drv_pixel_rst_n;
        byte_rst_n  = tx_if.drv_byte_rst_n;
    end

    // =========================================================================
    // I2C bus
    // =========================================================================
    assign i2c_scl_drv = tx_if.i2c_scl;
    assign i2c_sda_drv = tx_if.i2c_sda;
    assign i2c_sda_bus = i2c_sda_drv ? 1'bz : 1'b0;
    pullup(i2c_sda_bus);

    // =========================================================================
    // cfg sideband mirror: interface → module-level logic
    // always_ff on pclk captures driver blocking writes within one pclk cycle.
    // =========================================================================
    always_ff @(posedge pclk) begin
        cfg_active_lanes <= tx_if.cfg_active_lanes;
        cfg_frame_lines  <= tx_if.cfg_frame_lines;
        cfg_rx_data_type <= rx_if.cfg_rx_data_type;
    end

    // =========================================================================
    // Read-only reset and DUT output feeds into interfaces
    // =========================================================================
    assign tx_if.sys_rst_n   = sys_rst_n;
    assign tx_if.preset_n    = preset_n;
    assign tx_if.pixel_rst_n = pixel_rst_n;
    assign tx_if.byte_rst_n  = byte_rst_n;

    assign rx_if.sys_rst_n   = sys_rst_n;
    assign rx_if.preset_n    = preset_n;
    assign rx_if.pixel_rst_n = pixel_rst_n;
    assign rx_if.byte_rst_n  = byte_rst_n;

    assign tx_if.tx_axis_tready    = tx_axis_tready;
    assign tx_if.tx_apb_prdata     = tx_apb_prdata;
    assign tx_if.tx_apb_pready     = tx_apb_pready;
    assign tx_if.tx_lane0_data_out = tx_lane0_data_out;
    assign tx_if.tx_lane1_data_out = tx_lane1_data_out;
    assign tx_if.tx_lane2_data_out = tx_lane2_data_out;
    assign tx_if.tx_lane3_data_out = tx_lane3_data_out;
    assign tx_if.tx_lane0_vld_out  = tx_lane0_vld_out;
    assign tx_if.tx_lane1_vld_out  = tx_lane1_vld_out;
    assign tx_if.tx_lane2_vld_out  = tx_lane2_vld_out;
    assign tx_if.tx_lane3_vld_out  = tx_lane3_vld_out;
    assign tx_if.tx_req_hs_out     = tx_req_hs_out;

    assign rx_if.rx_axis_tdata  = rx_axis_tdata;
    assign rx_if.rx_axis_tkeep  = rx_axis_tkeep;
    assign rx_if.rx_axis_tlast  = rx_axis_tlast;
    assign rx_if.rx_axis_tuser  = rx_axis_tuser;
    assign rx_if.rx_axis_tvalid = rx_axis_tvalid;
    assign rx_if.rx_apb_prdata  = rx_apb_prdata;
    assign rx_if.rx_apb_pready  = rx_apb_pready;
    assign rx_if.rx_crc_ok      = rx_crc_ok;
    assign rx_if.rx_crc_done    = rx_crc_done;
    assign rx_if.rx_ecc_single  = rx_ecc_single;
    assign rx_if.rx_ecc_double  = rx_ecc_double;

    // =========================================================================
    // Packetizer debug tap
    // =========================================================================
    assign dig_tx_pkt_data_in = dut.u_csi2_tx_top.w_pkt_data;
    assign dig_tx_pkt_vld_in  = dut.u_csi2_tx_top.w_pkt_valid;

    pullup(tx_if.i2c_sda_bus);

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    mipi_system_top dut (
        .sys_clk(sys_clk),             .sys_rst_n(sys_rst_n),
        .pclk(pclk),                   .preset_n(preset_n),
        .pixel_clk(pixel_clk),         .pixel_rst_n(pixel_rst_n),
        .byte_clk(byte_clk),           .byte_rst_n(byte_rst_n),

        .cfg_active_lanes(cfg_active_lanes),
        .cfg_frame_lines(cfg_frame_lines),
        .cfg_rx_data_type(cfg_rx_data_type),

        .i2c_scl(tx_if.i2c_scl_drv), 
        .i2c_sda(tx_if.i2c_sda_bus),

        .tx_apb_psel(tx_if.tx_apb_psel),
        .tx_apb_penable(tx_if.tx_apb_penable),
        .tx_apb_pwrite(tx_if.tx_apb_pwrite),
        .tx_apb_paddr(tx_if.tx_apb_paddr),
        .tx_apb_pwdata(tx_if.tx_apb_pwdata),
        .tx_apb_prdata(tx_apb_prdata),
        .tx_apb_pready(tx_apb_pready),

        .rx_apb_psel(rx_if.rx_apb_psel),
        .rx_apb_penable(rx_if.rx_apb_penable),
        .rx_apb_pwrite(rx_if.rx_apb_pwrite),
        .rx_apb_paddr(rx_if.rx_apb_paddr),
        .rx_apb_pwdata(rx_if.rx_apb_pwdata),
        .rx_apb_prdata(rx_apb_prdata),
        .rx_apb_pready(rx_apb_pready),

        .tx_axis_tdata(tx_if.tx_axis_tdata),
        .tx_axis_tvalid(tx_if.tx_axis_tvalid),
        .tx_axis_tuser(tx_if.tx_axis_tuser),
        .tx_axis_tlast(tx_if.tx_axis_tlast),
        .tx_axis_tready(tx_axis_tready),

        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tready(rx_if.rx_axis_tready),

        .tx_lane0_data_out(tx_lane0_data_out), .tx_lane0_vld_out(tx_lane0_vld_out),
        .tx_lane1_data_out(tx_lane1_data_out), .tx_lane1_vld_out(tx_lane1_vld_out),
        .tx_lane2_data_out(tx_lane2_data_out), .tx_lane2_vld_out(tx_lane2_vld_out),
        .tx_lane3_data_out(tx_lane3_data_out), .tx_lane3_vld_out(tx_lane3_vld_out),
        .tx_req_hs_out(tx_req_hs_out),
        .dig_tx_pkt_data_in(dig_tx_pkt_data_in),
        .dig_tx_pkt_vld_in(dig_tx_pkt_vld_in),

        .ppi_tx_ClkRequestHS(ppi_tx_ClkRequestHS), .ppi_tx_ClkReadyHS(ppi_tx_ClkReadyHS),
        .ppi_tx_ByteClkHS(ppi_tx_ByteClkHS),        .ppi_tx_RequestHS(ppi_tx_RequestHS),
        .ppi_tx_ReadyHS(ppi_tx_ReadyHS),
        .ppi_tx_DataHS_0(ppi_tx_DataHS_0), .ppi_tx_DataHS_1(ppi_tx_DataHS_1),
        .ppi_tx_DataHS_2(ppi_tx_DataHS_2), .ppi_tx_DataHS_3(ppi_tx_DataHS_3),
        .ppi_tx_ValidHS_0(ppi_tx_ValidHS_0), .ppi_tx_ValidHS_1(ppi_tx_ValidHS_1),
        .ppi_tx_ValidHS_2(ppi_tx_ValidHS_2), .ppi_tx_ValidHS_3(ppi_tx_ValidHS_3),

        .ppi_rx_ByteClkHS(ppi_rx_ByteClkHS),
        .ppi_rx_DataHS_0(ppi_rx_DataHS_0), .ppi_rx_DataHS_1(ppi_rx_DataHS_1),
        .ppi_rx_DataHS_2(ppi_rx_DataHS_2), .ppi_rx_DataHS_3(ppi_rx_DataHS_3),
        .ppi_rx_ValidHS_0(ppi_rx_ValidHS_0),  .ppi_rx_ValidHS_1(ppi_rx_ValidHS_1),
        .ppi_rx_ValidHS_2(ppi_rx_ValidHS_2),  .ppi_rx_ValidHS_3(ppi_rx_ValidHS_3),
        .ppi_rx_ActiveHS_0(ppi_rx_ActiveHS_0),.ppi_rx_ActiveHS_1(ppi_rx_ActiveHS_1),
        .ppi_rx_ActiveHS_2(ppi_rx_ActiveHS_2),.ppi_rx_ActiveHS_3(ppi_rx_ActiveHS_3),
        .ppi_rx_SyncHS_0(ppi_rx_SyncHS_0),   .ppi_rx_SyncHS_1(ppi_rx_SyncHS_1),
        .ppi_rx_SyncHS_2(ppi_rx_SyncHS_2),   .ppi_rx_SyncHS_3(ppi_rx_SyncHS_3),

        .rx_crc_ok(rx_crc_ok), .rx_crc_done(rx_crc_done),
        .rx_ecc_single(rx_ecc_single), .rx_ecc_double(rx_ecc_double)
    );

    // =========================================================================
    // D-PHY
    // =========================================================================
    dphy_behavioral u_dphy (
        .i_clk_pll(clk_phy_pll), .i_rst_n(sys_rst_n),
        .i_TxClkRequestHS(ppi_tx_ClkRequestHS), .o_TxClkReadyHS(ppi_tx_ClkReadyHS),
        .o_TxByteClkHS(ppi_tx_ByteClkHS),
        .i_TxRequestHS(ppi_tx_RequestHS), .o_TxReadyHS(ppi_tx_ReadyHS),
        .i_TxDataHS_0(ppi_tx_DataHS_0), .i_TxDataHS_1(ppi_tx_DataHS_1),
        .i_TxDataHS_2(ppi_tx_DataHS_2), .i_TxDataHS_3(ppi_tx_DataHS_3),
        .i_TxValidHS_0(ppi_tx_ValidHS_0), .i_TxValidHS_1(ppi_tx_ValidHS_1),
        .i_TxValidHS_2(ppi_tx_ValidHS_2), .i_TxValidHS_3(ppi_tx_ValidHS_3),
        .o_RxByteClkHS(ppi_rx_ByteClkHS),
        .o_RxDataHS_0(ppi_rx_DataHS_0), .o_RxDataHS_1(ppi_rx_DataHS_1),
        .o_RxDataHS_2(ppi_rx_DataHS_2), .o_RxDataHS_3(ppi_rx_DataHS_3),
        .o_RxValidHS_0(ppi_rx_ValidHS_0),  .o_RxValidHS_1(ppi_rx_ValidHS_1),
        .o_RxValidHS_2(ppi_rx_ValidHS_2),  .o_RxValidHS_3(ppi_rx_ValidHS_3),
        .o_RxActiveHS_0(ppi_rx_ActiveHS_0),.o_RxActiveHS_1(ppi_rx_ActiveHS_1),
        .o_RxActiveHS_2(ppi_rx_ActiveHS_2),.o_RxActiveHS_3(ppi_rx_ActiveHS_3),
        .o_RxSyncHS_0(ppi_rx_SyncHS_0),   .o_RxSyncHS_1(ppi_rx_SyncHS_1),
        .o_RxSyncHS_2(ppi_rx_SyncHS_2),   .o_RxSyncHS_3(ppi_rx_SyncHS_3)
    );

    // =========================================================================
    // SVA
    // =========================================================================
    csi_sva u_csi_sva (
        .pixel_clk(pixel_clk),       .byte_clk(byte_clk),      .sys_rst_n(sys_rst_n),
        .tx_axis_tdata(tx_if.tx_axis_tdata),
        .tx_axis_tvalid(tx_if.tx_axis_tvalid),
        .tx_axis_tready(tx_axis_tready),
        .tx_axis_tuser(tx_if.tx_axis_tuser),
        .tx_axis_tlast(tx_if.tx_axis_tlast),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tready(rx_if.rx_axis_tready),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),
        .rx_crc_ok(rx_crc_ok),       .rx_crc_done(rx_crc_done),
        .rx_ecc_single(rx_ecc_single),.rx_ecc_double(rx_ecc_double)
    );

    // =========================================================================
    // Initial block: perform first hard reset, then release.
    // The driver's reinit() does only APB soft-reset for subsequent frames
    // (matching reference TB), so drv_* stay 1 after this initial sequence.
    // =========================================================================
    initial begin
        // Pre-load sideband fields to valid defaults
        tx_if.cfg_active_lanes = 3'd4;
        tx_if.cfg_frame_lines  = NUM_LINES;
        rx_if.cfg_rx_data_type = 6'h2A;
        rx_if.cfg_active_lanes = 3'd4;
        rx_if.rx_axis_tready   = 1'b1;

        // drv_* are already 0 from interface defaults → sys_rst_n=0 via always_comb
        // Wait then release the initial reset
        repeat(10) @(posedge sys_clk);
        tx_if.drv_sys_rst_n   = 1;
        tx_if.drv_preset_n    = 1;
        tx_if.drv_pixel_rst_n = 1;
        tx_if.drv_byte_rst_n  = 1;
        repeat(10) @(posedge byte_clk);
        // drv_* stay 1 from here – reinit() uses APB soft-reset only
    end

    // =========================================================================
    // UVM config_db + run_test
    // =========================================================================
    initial begin
        uvm_config_db #(virtual csi_tx_if)::set(null, "uvm_test_top*", "tx_vif", tx_if);
        uvm_config_db #(virtual csi_rx_if)::set(null, "uvm_test_top*", "rx_vif", rx_if);
        run_test("csi_system_test");
    end

    // =========================================================================
    // Timeout
    // =========================================================================
    initial begin
        #2_000_000_000;
        `uvm_fatal("TIMEOUT", "Simulation exceeded 2 s.")
    end

endmodule : csi_tb_top