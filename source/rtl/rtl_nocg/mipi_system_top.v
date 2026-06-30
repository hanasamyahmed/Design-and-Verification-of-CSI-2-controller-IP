`timescale 1ns / 1ps

module mipi_system_top (
    input  wire        sys_clk, sys_rst_n,
    input  wire        pclk, preset_n,
    input  wire        pixel_clk, pixel_rst_n,
    input  wire        byte_clk, byte_rst_n,
    input  wire [2:0]  cfg_active_lanes,
    input  wire [15:0] cfg_frame_lines,
    input  wire [5:0]  cfg_rx_data_type,
    
    input  wire        i2c_scl,
    inout  wire        i2c_sda,

    // TX APB
    input  wire        tx_apb_psel, tx_apb_penable, tx_apb_pwrite,
    input  wire [31:0] tx_apb_paddr, tx_apb_pwdata,
    output wire [31:0] tx_apb_prdata, output wire tx_apb_pready,

    // RX APB
    input  wire        rx_apb_psel, rx_apb_penable, rx_apb_pwrite,
    input  wire [31:0] rx_apb_paddr, rx_apb_pwdata,
    output wire [31:0] rx_apb_prdata, output wire rx_apb_pready,

    // AXI TX
    input  wire [31:0] tx_axis_tdata,
    input  wire        tx_axis_tvalid, tx_axis_tuser, tx_axis_tlast,
    output wire        tx_axis_tready,

    // AXI RX
    output wire [31:0] rx_axis_tdata,
    output wire [3:0]  rx_axis_tkeep,
    output wire        rx_axis_tlast, rx_axis_tuser, rx_axis_tvalid,
    input  wire        rx_axis_tready,

    // Outputs for TB Loopback
    output wire [7:0]  tx_lane0_data_out, tx_lane1_data_out, tx_lane2_data_out, tx_lane3_data_out,
    output wire        tx_lane0_vld_out, tx_lane1_vld_out, tx_lane2_vld_out, tx_lane3_vld_out,
    output wire        tx_req_hs_out,
    
    // Taps for TB
    input  wire [7:0]  dig_tx_pkt_data_in,
    input  wire        dig_tx_pkt_vld_in,

    // PPI TX
    output wire        ppi_tx_ClkRequestHS,
    input  wire        ppi_tx_ClkReadyHS, ppi_tx_ByteClkHS,
    output wire [3:0]  ppi_tx_RequestHS,
    input  wire [3:0]  ppi_tx_ReadyHS,
    output wire [7:0]  ppi_tx_DataHS_0, ppi_tx_DataHS_1, ppi_tx_DataHS_2, ppi_tx_DataHS_3,
    output wire        ppi_tx_ValidHS_0, ppi_tx_ValidHS_1, ppi_tx_ValidHS_2, ppi_tx_ValidHS_3,

    // PPI RX
    input  wire        ppi_rx_ByteClkHS,
    input  wire [7:0]  ppi_rx_DataHS_0, ppi_rx_DataHS_1, ppi_rx_DataHS_2, ppi_rx_DataHS_3,
    input  wire        ppi_rx_ValidHS_0, ppi_rx_ValidHS_1, ppi_rx_ValidHS_2, ppi_rx_ValidHS_3,
    input  wire        ppi_rx_ActiveHS_0, ppi_rx_ActiveHS_1, ppi_rx_ActiveHS_2, ppi_rx_ActiveHS_3,
    input  wire        ppi_rx_SyncHS_0, ppi_rx_SyncHS_1, ppi_rx_SyncHS_2, ppi_rx_SyncHS_3,

    // Status
    output wire        rx_crc_ok, rx_crc_done, rx_ecc_single, rx_ecc_double
);

    mipi_tx_top u_csi2_tx_top (
        .sys_clk(sys_clk), .pclk(pclk), .pixel_clk(pixel_clk), .byte_clk(byte_clk),
        .sys_rst_n(sys_rst_n), .preset_n(preset_n), .pixel_rst_n(pixel_rst_n), .byte_rst_n(byte_rst_n),
        .cfg_active_lanes(cfg_active_lanes), .cfg_frame_lines(cfg_frame_lines),
        .tx_apb_psel(tx_apb_psel), .tx_apb_penable(tx_apb_penable), .tx_apb_pwrite(tx_apb_pwrite),
        .tx_apb_paddr(tx_apb_paddr), .tx_apb_pwdata(tx_apb_pwdata), .tx_apb_prdata(tx_apb_prdata), .tx_apb_pready(tx_apb_pready),
        .i2c_scl(i2c_scl), .i2c_sda(i2c_sda),
        .tx_axis_tdata(tx_axis_tdata), .tx_axis_tvalid(tx_axis_tvalid), .tx_axis_tuser(tx_axis_tuser), .tx_axis_tlast(tx_axis_tlast), .tx_axis_tready(tx_axis_tready),
        .ppi_tx_ClkRequestHS(ppi_tx_ClkRequestHS), .ppi_tx_ClkReadyHS(ppi_tx_ClkReadyHS), .ppi_tx_ByteClkHS(ppi_tx_ByteClkHS),
        .ppi_tx_RequestHS(ppi_tx_RequestHS), .ppi_tx_ReadyHS(ppi_tx_ReadyHS),
        .ppi_tx_DataHS_0(ppi_tx_DataHS_0), .ppi_tx_DataHS_1(ppi_tx_DataHS_1), .ppi_tx_DataHS_2(ppi_tx_DataHS_2), .ppi_tx_DataHS_3(ppi_tx_DataHS_3),
        .ppi_tx_ValidHS_0(ppi_tx_ValidHS_0), .ppi_tx_ValidHS_1(ppi_tx_ValidHS_1), .ppi_tx_ValidHS_2(ppi_tx_ValidHS_2), .ppi_tx_ValidHS_3(ppi_tx_ValidHS_3),
        .tx_lane0_data_out(tx_lane0_data_out), .tx_lane1_data_out(tx_lane1_data_out), .tx_lane2_data_out(tx_lane2_data_out), .tx_lane3_data_out(tx_lane3_data_out),
        .tx_lane0_vld_out(tx_lane0_vld_out), .tx_lane1_vld_out(tx_lane1_vld_out), .tx_lane2_vld_out(tx_lane2_vld_out), .tx_lane3_vld_out(tx_lane3_vld_out),
        .tx_req_hs_out(tx_req_hs_out)
    );

    mipi_rx_top u_csi2_rx_top (
        .sys_clk(sys_clk), .pclk(pclk), .pixel_clk(pixel_clk), .byte_clk(byte_clk),
        .sys_rst_n(sys_rst_n), .preset_n(preset_n), .pixel_rst_n(pixel_rst_n), .byte_rst_n(byte_rst_n),
        .cfg_active_lanes(cfg_active_lanes), .cfg_rx_data_type(cfg_rx_data_type),
        .rx_apb_psel(rx_apb_psel), .rx_apb_penable(rx_apb_penable), .rx_apb_pwrite(rx_apb_pwrite),
        .rx_apb_paddr(rx_apb_paddr), .rx_apb_pwdata(rx_apb_pwdata), .rx_apb_prdata(rx_apb_prdata), .rx_apb_pready(rx_apb_pready),
        .i2c_scl(i2c_scl), .i2c_sda(i2c_sda),
        .ppi_rx_ByteClkHS(ppi_rx_ByteClkHS),
        .ppi_rx_DataHS_0(ppi_rx_DataHS_0), .ppi_rx_DataHS_1(ppi_rx_DataHS_1), .ppi_rx_DataHS_2(ppi_rx_DataHS_2), .ppi_rx_DataHS_3(ppi_rx_DataHS_3),
        .ppi_rx_ValidHS_0(ppi_rx_ValidHS_0), .ppi_rx_ValidHS_1(ppi_rx_ValidHS_1), .ppi_rx_ValidHS_2(ppi_rx_ValidHS_2), .ppi_rx_ValidHS_3(ppi_rx_ValidHS_3),
        .ppi_rx_ActiveHS_0(ppi_rx_ActiveHS_0), .ppi_rx_ActiveHS_1(ppi_rx_ActiveHS_1), .ppi_rx_ActiveHS_2(ppi_rx_ActiveHS_2), .ppi_rx_ActiveHS_3(ppi_rx_ActiveHS_3),
        .ppi_rx_SyncHS_0(ppi_rx_SyncHS_0), .ppi_rx_SyncHS_1(ppi_rx_SyncHS_1), .ppi_rx_SyncHS_2(ppi_rx_SyncHS_2), .ppi_rx_SyncHS_3(ppi_rx_SyncHS_3),
        .rx_axis_tdata(rx_axis_tdata), .rx_axis_tkeep(rx_axis_tkeep), .rx_axis_tlast(rx_axis_tlast), .rx_axis_tuser(rx_axis_tuser), .rx_axis_tvalid(rx_axis_tvalid), .rx_axis_tready(rx_axis_tready),
        .rx_crc_ok(rx_crc_ok), .rx_crc_done(rx_crc_done), .rx_ecc_single(rx_ecc_single), .rx_ecc_double(rx_ecc_double)
    );

endmodule
