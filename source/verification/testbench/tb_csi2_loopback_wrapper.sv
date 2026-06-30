// =============================================================================
// FILE        : tb_csi2_loopback_wrapper.sv
// Author       : Hana Samy
// Date         : June 2026
// DESCRIPTION : Thin wrapper testbench for the MIPI CSI-2 loopback system.
//
//   This file contains ONLY:
//     1. Signal declarations
//     2. DUT instantiation
//     3. SVA / D-PHY model instantiation
//     4. Clock generators
//     5. A single initial block that picks a test mode and calls run_test()
//
//   All tasks, functions, memories, and monitors live in:
//       csi2_tasks.svh
//   which is `included after the signal declarations but inside the module.
//
// =============================================================================
// AVAILABLE TEST MODES
// -----------------------------------------------------------------------------
//  Mode │ Name                        │ Description
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   0   │ FULL_REGRESSION             │ All DTs × NUM_FRAMES × lane sweep
//       │                             │ (CRC/SCRAM toggled) + CRC injection +
//       │                             │ ECC injection + RAW10 sanity frame
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   1   │ RAW8_DT_SWEEP               │ DT=RAW8  (0x2A, 8 bpp)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   2   │ YUV422_DT_SWEEP             │ DT=YUV422 (0x1E, 16 bpp, 2 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   3   │ RGB565_DT_SWEEP             │ DT=RGB565 (0x22, 16 bpp, 2 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   4   │ RGB888_DT_SWEEP             │ DT=RGB888 (0x24, 24 bpp, 3 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   5   │ RAW10_DT_SWEEP              │ DT=RAW10  (0x2B, 10 bpp, 1.25 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   6   │ CRC_INJECT_ONLY             │ CRC 1-bit / 2-bit / 3-bit injection
//       │                             │ DT=RAW8, 4 lanes
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   7   │ ECC_INJECT_ONLY             │ ECC single-bit (SEC) + double-bit (DED)
//       │                             │ injection — DT=RAW8, 4 lanes
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   8   │ MULTI_DT_SMOKE              │ 1 frame per DT (RAW8, YUV422, RGB565,
//       │                             │ RGB888, RAW10), 4 lanes, CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   9   │ SCRAMBLER_CRC_TOGGLE        │ All 4 {CRC,SCRAM} combos for every DT
//       │                             │ (RAW8, YUV422, RGB565, RGB888, RAW10)
//       │                             │ Fixed at 4 lanes throughout
// =============================================================================
// HOW TO SELECT A MODE
//   Change the parameter below:
//       parameter int TEST_MODE = 0;   // ← edit this number
//   Or override it from the simulator command line, e.g.:
//       vlog  tb_csi2_loopback_wrapper.sv  +define+TEST_MODE=3
//       vsim  tb_csi2_loopback_wrapper -gTEST_MODE=3
// =============================================================================

`timescale 1ns / 1ps
import csi_coverage_pkg::*;

module tb_csi2_loopback_wrapper;

    // =========================================================================
    // TEST MODE SELECTION
    //   Change this one number to switch between scenarios (see table above).
    // =========================================================================
    parameter int TEST_MODE = 0;

    // =========================================================================
    // DUT PORT SIGNALS
    // =========================================================================
    logic pclk     = 0, preset_n     = 0;
    logic pixel_clk= 0, pixel_rst_n  = 0;
    logic byte_clk = 0, byte_rst_n   = 0;

    logic [2:0]  cfg_active_lanes   = 3'd4;
    logic [15:0] cfg_frame_lines;           // driven by reinit()
    logic [5:0]  cfg_rx_data_type   = 6'h2A;

    // TX APB
    logic        tx_apb_psel = 0, tx_apb_penable = 0, tx_apb_pwrite = 0;
    logic [31:0] tx_apb_paddr= 0, tx_apb_pwdata  = 0;
    wire  [31:0] tx_apb_prdata;
    wire         tx_apb_pready;

    // RX APB
    logic        rx_apb_psel = 0, rx_apb_penable = 0, rx_apb_pwrite = 0;
    logic [31:0] rx_apb_paddr= 0, rx_apb_pwdata  = 0;
    wire  [31:0] rx_apb_prdata;
    wire         rx_apb_pready;

    // TX AXI-Stream
    logic [31:0] tx_axis_tdata  = 0;
    logic        tx_axis_tvalid = 0, tx_axis_tuser = 0, tx_axis_tlast = 0;
    wire         tx_axis_tready;

    // RX AXI-Stream
    wire  [31:0] rx_axis_tdata;
    wire  [3:0]  rx_axis_tkeep;
    wire         rx_axis_tlast, rx_axis_tuser, rx_axis_tvalid;
    logic        rx_axis_tready = 1;

    // TX lane outputs
    wire [7:0] tx_lane0_data_out, tx_lane1_data_out,
               tx_lane2_data_out, tx_lane3_data_out;
    wire       tx_lane0_vld_out,  tx_lane1_vld_out,
               tx_lane2_vld_out,  tx_lane3_vld_out;
    wire       tx_req_hs_out;
    wire [7:0] dig_tx_pkt_data_in;
    wire       dig_tx_pkt_vld_in;

    // PPI TX
    wire       ppi_tx_ClkRequestHS, ppi_tx_ClkReadyHS, ppi_tx_ByteClkHS;
    wire [3:0] ppi_tx_RequestHS,    ppi_tx_ReadyHS;
    wire [7:0] ppi_tx_DataHS_0, ppi_tx_DataHS_1,
               ppi_tx_DataHS_2, ppi_tx_DataHS_3;
    wire       ppi_tx_ValidHS_0, ppi_tx_ValidHS_1,
               ppi_tx_ValidHS_2, ppi_tx_ValidHS_3;

    // PPI RX
    wire       ppi_rx_ByteClkHS;
    wire [7:0] ppi_rx_DataHS_0,   ppi_rx_DataHS_1,
               ppi_rx_DataHS_2,   ppi_rx_DataHS_3;
    wire       ppi_rx_ValidHS_0,  ppi_rx_ValidHS_1,
               ppi_rx_ValidHS_2,  ppi_rx_ValidHS_3;
    wire       ppi_rx_ActiveHS_0, ppi_rx_ActiveHS_1,
               ppi_rx_ActiveHS_2, ppi_rx_ActiveHS_3;
    wire       ppi_rx_SyncHS_0,   ppi_rx_SyncHS_1,
               ppi_rx_SyncHS_2,   ppi_rx_SyncHS_3;

    // Status outputs
    wire rx_crc_ok, rx_crc_done, rx_ecc_single, rx_ecc_double;

    // =========================================================================
    // I2C SIGNALS & PULL-UPS
    // =========================================================================
    logic i2c_scl_drv = 1;
    logic i2c_sda_drv = 1;
    wire  i2c_sda_bus;
    assign i2c_sda_bus = i2c_sda_drv ? 1'bz : 1'b0;
    pullup (i2c_sda_bus);

    // =========================================================================
    // INTERNAL PACKETISER BRIDGE
    // =========================================================================
    assign dig_tx_pkt_data_in = dut.u_csi2_tx_top.w_pkt_data;
    assign dig_tx_pkt_vld_in  = dut.u_csi2_tx_top.w_pkt_valid;

    // =========================================================================
    // DUT INSTANTIATION
    // =========================================================================
    mipi_system_top dut (
        .pclk               (pclk),               .preset_n            (preset_n),
        .pixel_clk          (pixel_clk),           .pixel_rst_n         (pixel_rst_n),
        .byte_clk           (byte_clk),            .byte_rst_n          (byte_rst_n),

        .cfg_active_lanes   (cfg_active_lanes),
        .cfg_frame_lines    (cfg_frame_lines),
        .cfg_rx_data_type   (cfg_rx_data_type),

        .i2c_scl            (i2c_scl_drv),
        .i2c_sda            (i2c_sda_bus),

        .tx_apb_psel        (tx_apb_psel),         .tx_apb_penable      (tx_apb_penable),
        .tx_apb_pwrite      (tx_apb_pwrite),        .tx_apb_paddr        (tx_apb_paddr),
        .tx_apb_pwdata      (tx_apb_pwdata),        .tx_apb_prdata       (tx_apb_prdata),
        .tx_apb_pready      (tx_apb_pready),

        .rx_apb_psel        (rx_apb_psel),         .rx_apb_penable      (rx_apb_penable),
        .rx_apb_pwrite      (rx_apb_pwrite),        .rx_apb_paddr        (rx_apb_paddr),
        .rx_apb_pwdata      (rx_apb_pwdata),        .rx_apb_prdata       (rx_apb_prdata),
        .rx_apb_pready      (rx_apb_pready),

        .tx_axis_tdata      (tx_axis_tdata),        .tx_axis_tvalid      (tx_axis_tvalid),
        .tx_axis_tuser      (tx_axis_tuser),        .tx_axis_tlast       (tx_axis_tlast),
        .tx_axis_tready     (tx_axis_tready),

        .rx_axis_tdata      (rx_axis_tdata),        .rx_axis_tkeep       (rx_axis_tkeep),
        .rx_axis_tlast      (rx_axis_tlast),        .rx_axis_tuser       (rx_axis_tuser),
        .rx_axis_tvalid     (rx_axis_tvalid),       .rx_axis_tready      (rx_axis_tready),

        .tx_lane0_data_out  (tx_lane0_data_out),    .tx_lane0_vld_out    (tx_lane0_vld_out),
        .tx_lane1_data_out  (tx_lane1_data_out),    .tx_lane1_vld_out    (tx_lane1_vld_out),
        .tx_lane2_data_out  (tx_lane2_data_out),    .tx_lane2_vld_out    (tx_lane2_vld_out),
        .tx_lane3_data_out  (tx_lane3_data_out),    .tx_lane3_vld_out    (tx_lane3_vld_out),
        .tx_req_hs_out      (tx_req_hs_out),

        .dig_tx_pkt_data_in (dig_tx_pkt_data_in),   .dig_tx_pkt_vld_in   (dig_tx_pkt_vld_in),

        .ppi_tx_ClkRequestHS(ppi_tx_ClkRequestHS),  .ppi_tx_ClkReadyHS   (ppi_tx_ClkReadyHS),
        .ppi_tx_ByteClkHS   (ppi_tx_ByteClkHS),     .ppi_tx_RequestHS    (ppi_tx_RequestHS),
        .ppi_tx_ReadyHS     (ppi_tx_ReadyHS),
        .ppi_tx_DataHS_0    (ppi_tx_DataHS_0),       .ppi_tx_DataHS_1     (ppi_tx_DataHS_1),
        .ppi_tx_DataHS_2    (ppi_tx_DataHS_2),       .ppi_tx_DataHS_3     (ppi_tx_DataHS_3),
        .ppi_tx_ValidHS_0   (ppi_tx_ValidHS_0),      .ppi_tx_ValidHS_1    (ppi_tx_ValidHS_1),
        .ppi_tx_ValidHS_2   (ppi_tx_ValidHS_2),      .ppi_tx_ValidHS_3    (ppi_tx_ValidHS_3),

        .ppi_rx_ByteClkHS   (ppi_rx_ByteClkHS),
        .ppi_rx_DataHS_0    (ppi_rx_DataHS_0),       .ppi_rx_DataHS_1     (ppi_rx_DataHS_1),
        .ppi_rx_DataHS_2    (ppi_rx_DataHS_2),       .ppi_rx_DataHS_3     (ppi_rx_DataHS_3),
        .ppi_rx_ValidHS_0   (ppi_rx_ValidHS_0),      .ppi_rx_ValidHS_1    (ppi_rx_ValidHS_1),
        .ppi_rx_ValidHS_2   (ppi_rx_ValidHS_2),      .ppi_rx_ValidHS_3    (ppi_rx_ValidHS_3),
        .ppi_rx_ActiveHS_0  (ppi_rx_ActiveHS_0),     .ppi_rx_ActiveHS_1   (ppi_rx_ActiveHS_1),
        .ppi_rx_ActiveHS_2  (ppi_rx_ActiveHS_2),     .ppi_rx_ActiveHS_3   (ppi_rx_ActiveHS_3),
        .ppi_rx_SyncHS_0    (ppi_rx_SyncHS_0),       .ppi_rx_SyncHS_1     (ppi_rx_SyncHS_1),
        .ppi_rx_SyncHS_2    (ppi_rx_SyncHS_2),       .ppi_rx_SyncHS_3     (ppi_rx_SyncHS_3),

        .rx_crc_ok          (rx_crc_ok),             .rx_crc_done         (rx_crc_done),
        .rx_ecc_single      (rx_ecc_single),         .rx_ecc_double       (rx_ecc_double)
    );

    // =========================================================================
    // SVA PROTOCOL MONITOR
    // =========================================================================
    csi_sva u_sva_mon (
        .pixel_clk      (pixel_clk),
        .byte_clk       (byte_clk),
        .sys_rst_n      (byte_rst_n),
        .tx_axis_tdata  (tx_axis_tdata),
        .tx_axis_tvalid (tx_axis_tvalid),
        .tx_axis_tready (tx_axis_tready),
        .tx_axis_tuser  (tx_axis_tuser),
        .tx_axis_tlast  (tx_axis_tlast),
        .rx_axis_tdata  (rx_axis_tdata),
        .rx_axis_tvalid (rx_axis_tvalid),
        .rx_axis_tready (rx_axis_tready),
        .rx_axis_tlast  (rx_axis_tlast),
        .rx_axis_tuser  (rx_axis_tuser),
        .rx_crc_ok      (rx_crc_ok),
        .rx_crc_done    (rx_crc_done),
        .rx_ecc_single  (rx_ecc_single),
        .rx_ecc_double  (rx_ecc_double)
    );

    // =========================================================================
    // D-PHY PLL & BEHAVIOURAL MODEL
    // =========================================================================
    logic clk_phy_pll = 0;
    real  phy_half_period = 3.125;

    always @(*) begin
        if      (cfg_active_lanes == 3'd4) phy_half_period = 3.125;
        else if (cfg_active_lanes == 3'd2) phy_half_period = 6.250;
        else                               phy_half_period = 12.50;
    end
    always #phy_half_period clk_phy_pll = ~clk_phy_pll;

    dphy_behavioral u_dphy (
        .i_clk_pll        (clk_phy_pll),
        .i_rst_n          (byte_rst_n),
        .i_TxClkRequestHS (ppi_tx_ClkRequestHS), .o_TxClkReadyHS  (ppi_tx_ClkReadyHS),
        .o_TxByteClkHS    (ppi_tx_ByteClkHS),
        .i_TxRequestHS    (ppi_tx_RequestHS),    .o_TxReadyHS     (ppi_tx_ReadyHS),
        .i_TxDataHS_0     (ppi_tx_DataHS_0),     .i_TxDataHS_1    (ppi_tx_DataHS_1),
        .i_TxDataHS_2     (ppi_tx_DataHS_2),     .i_TxDataHS_3    (ppi_tx_DataHS_3),
        .i_TxValidHS_0    (ppi_tx_ValidHS_0),    .i_TxValidHS_1   (ppi_tx_ValidHS_1),
        .i_TxValidHS_2    (ppi_tx_ValidHS_2),    .i_TxValidHS_3   (ppi_tx_ValidHS_3),
        .o_RxByteClkHS    (ppi_rx_ByteClkHS),
        .o_RxDataHS_0     (ppi_rx_DataHS_0),     .o_RxDataHS_1    (ppi_rx_DataHS_1),
        .o_RxDataHS_2     (ppi_rx_DataHS_2),     .o_RxDataHS_3    (ppi_rx_DataHS_3),
        .o_RxValidHS_0    (ppi_rx_ValidHS_0),    .o_RxValidHS_1   (ppi_rx_ValidHS_1),
        .o_RxValidHS_2    (ppi_rx_ValidHS_2),    .o_RxValidHS_3   (ppi_rx_ValidHS_3),
        .o_RxActiveHS_0   (ppi_rx_ActiveHS_0),   .o_RxActiveHS_1  (ppi_rx_ActiveHS_1),
        .o_RxActiveHS_2   (ppi_rx_ActiveHS_2),   .o_RxActiveHS_3  (ppi_rx_ActiveHS_3),
        .o_RxSyncHS_0     (ppi_rx_SyncHS_0),     .o_RxSyncHS_1    (ppi_rx_SyncHS_1),
        .o_RxSyncHS_2     (ppi_rx_SyncHS_2),     .o_RxSyncHS_3    (ppi_rx_SyncHS_3)
    );

    // =========================================================================
    // CLOCK GENERATORS  (real SDC timings)
    // =========================================================================
    always #10.00 pclk      = ~pclk;       // 50 MHz  APB
    always #25.00 pixel_clk = ~pixel_clk;  // 40 MHz  pixel/AXI
    always #12.50 byte_clk  = ~byte_clk;   // 40 MHz  byte (matched to pixel)

    // =========================================================================
    // COVERAGE OBJECT
    //   Declared here (inside the module) so the package type imported at the
    //   top of this file is already in scope at elaboration time.
    //   The SVH tasks reference it directly via the enclosing module scope.
    // =========================================================================
    csi_coverage cov;

    // =========================================================================
    // SHARED TASK LIBRARY
    //   `include must come AFTER all signal declarations so that tasks can
    //   reference the signals above directly, without any port or virtual-
    //   interface indirection.
    // =========================================================================
    `include "csi2_tasks.svh"

    // =========================================================================
    // TOP-LEVEL TEST ENTRY POINT
    //   One line selects which scenario runs.  Everything else lives in the SVH.
    // =========================================================================
    initial begin
        run_test(TEST_MODE);
    end

    // =========================================================================
    // TIMEOUT WATCHDOG
    // =========================================================================
    initial begin
        #2_000_000_000;
        $display("[TIMEOUT] Simulation exceeded 2 s wall-clock – aborting.");
        $finish;
    end

endmodule