// =============================================================================
// File : csi_if.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : Virtual interfaces for the CSI-2 UVM environment.
//               Two interfaces:
//                 csi_tx_if  – pixel input  (driven by UVM driver)
//                 csi_rx_if  – pixel output (observed by UVM monitor)
//
// KEY DESIGN DECISIONS (learned from extensive debug):
//
//  1. cfg_active_lanes, cfg_frame_lines, cfg_rx_data_type are declared as
//     plain 'logic' fields in the interface.  The driver writes them using
//     BLOCKING assignments (=) so the module-level always_ff in csi_tb_top
//     can capture them on the next pclk edge.
//
//  2. The reset signals come in TWO flavours on csi_tx_if:
//       • sys_rst_n / preset_n / pixel_rst_n / byte_rst_n  (inputs from DUT /
//         module – the driver READS these to know when reset is de-asserted)
//       • drv_sys_rst_n / drv_preset_n / drv_pixel_rst_n / drv_byte_rst_n
//         (outputs – the driver WRITES these; csi_tb_top wires them back to
//         the module-level reset logics so reinit() can assert hard reset
//         exactly like the reference testbench does)
//
//  3. i2c_scl and i2c_sda are plain 'logic' (not tri/wire).  The driver
//     drives them; csi_tb_top routes them to i2c_scl_drv / i2c_sda_drv
//     which feed the pullup-based bus.
// =============================================================================
 
// -----------------------------------------------------------------------------
// TX Interface  (pixel input side)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
interface csi_tx_if (
    input logic pixel_clk,
    input logic pclk,
    input logic byte_clk,
    input logic sys_clk
);
 
    // -------------------------------------------------------------------------
    // AXI-Stream TX (driven by driver → DUT)
    // -------------------------------------------------------------------------
    logic [31:0] tx_axis_tdata  = 0;
    logic        tx_axis_tvalid = 0;
    logic        tx_axis_tuser  = 0;
    logic        tx_axis_tlast  = 0;
    logic        tx_axis_tready;       // DUT output – read by driver
 
    // -------------------------------------------------------------------------
    // APB TX (driven by driver → DUT)
    // -------------------------------------------------------------------------
    logic        tx_apb_psel    = 0;
    logic        tx_apb_penable = 0;
    logic        tx_apb_pwrite  = 0;
    logic [31:0] tx_apb_paddr   = 0;
    logic [31:0] tx_apb_pwdata  = 0;
    logic [31:0] tx_apb_prdata;        // DUT output – read by driver
    logic        tx_apb_pready;        // DUT output – read by driver
 
    // -------------------------------------------------------------------------
    // I2C (driven by driver → shared bus in tb_top)
    // -------------------------------------------------------------------------
    logic i2c_scl = 1;
    logic i2c_sda = 1;

    // 1. Add the I2C Driving variables
    logic i2c_scl_drv = 1;
    logic i2c_sda_drv = 1;
    wire  i2c_sda_bus;
    assign i2c_sda_bus = i2c_sda_drv ? 1'bz : 1'b0;
 
    // -------------------------------------------------------------------------
    // Sideband configuration (written by driver using blocking =)
    // tb_top mirrors to module-level cfg_active_lanes etc via always_ff
    // -------------------------------------------------------------------------
    logic [2:0]  cfg_active_lanes = 3'd4;
    logic [15:0] cfg_frame_lines  = 100;
 
    // -------------------------------------------------------------------------
    // Reset signals – read-only for the driver (fed in from tb_top)
    // -------------------------------------------------------------------------
    logic sys_rst_n;
    logic preset_n;
    logic pixel_rst_n;
    logic byte_rst_n;
 
    // -------------------------------------------------------------------------
    // Driver-controlled reset outputs
    // The driver writes these with blocking = to assert/deassert hard reset
    // (mirrors the direct signal assignments in the reference TB reinit task).
    // tb_top wires these back to the module-level sys_rst_n etc via always_comb.
    // -------------------------------------------------------------------------
    logic drv_sys_rst_n   = 0;
    logic drv_preset_n    = 0;
    logic drv_pixel_rst_n = 0;
    logic drv_byte_rst_n  = 0;
 
    // -------------------------------------------------------------------------
    // Debug taps (DUT outputs, read by TX monitor)
    // -------------------------------------------------------------------------
    logic [7:0] tx_lane0_data_out;
    logic [7:0] tx_lane1_data_out;
    logic [7:0] tx_lane2_data_out;
    logic [7:0] tx_lane3_data_out;
    logic       tx_lane0_vld_out;
    logic       tx_lane1_vld_out;
    logic       tx_lane2_vld_out;
    logic       tx_lane3_vld_out;
    logic       tx_req_hs_out;


// ---> ADD THESE VARIABLES FOR COVERAGE TRACKING <---
    logic       cfg_crc_en;
    logic       cfg_scram_en;
     logic [5:0] cfg_rx_data_type;

    // 2. Add the Bit-Banging Tasks natively in the interface
    task automatic i2c_start;
        begin
            i2c_sda_drv = 0; #100;
            i2c_scl_drv = 0; #100;
        end
    endtask

    task automatic i2c_stop;
        begin
            i2c_sda_drv = 0; #100;
            i2c_scl_drv = 1; #100;
            i2c_sda_drv = 1; #100;
        end
    endtask

    task automatic i2c_write_byte(input logic [7:0] data);
        begin
            for (int i = 7; i >= 0; i--) begin
                i2c_sda_drv = data[i]; #100;
                i2c_scl_drv = 1;       #200;
                i2c_scl_drv = 0;       #100;
            end
            i2c_sda_drv = 1; #100;
            i2c_scl_drv = 1; #200;
            i2c_scl_drv = 0; #100;
        end
    endtask

    task automatic i2c_write_reg(input logic [6:0] slave_addr, input logic [15:0] reg_addr, input logic [7:0] data);
        begin
            i2c_start();
            i2c_write_byte({slave_addr, 1'b0}); 
            i2c_write_byte(reg_addr[15:8]);     
            i2c_write_byte(reg_addr[7:0]);      
            i2c_write_byte(data);               
            i2c_stop();
            #1000; 
        end
    endtask
 
endinterface : csi_tx_if
 
 
// -----------------------------------------------------------------------------
// RX Interface  (pixel output side)
// -----------------------------------------------------------------------------
interface csi_rx_if (
    input logic pixel_clk,
    input logic pclk,
    input logic byte_clk,
    input logic sys_clk
);
 
    // -------------------------------------------------------------------------
    // AXI-Stream RX (DUT outputs, observed by rx_monitor)
    // -------------------------------------------------------------------------
    logic [31:0] rx_axis_tdata;
    logic [3:0]  rx_axis_tkeep;
    logic        rx_axis_tlast;
    logic        rx_axis_tuser;
    logic        rx_axis_tvalid;
    logic        rx_axis_tready = 1;   // always-ready sink
 
    // -------------------------------------------------------------------------
    // APB RX (driven by driver → DUT RX register file)
    // -------------------------------------------------------------------------
    logic        rx_apb_psel    = 0;
    logic        rx_apb_penable = 0;
    logic        rx_apb_pwrite  = 0;
    logic [31:0] rx_apb_paddr   = 0;
    logic [31:0] rx_apb_pwdata  = 0;
    logic [31:0] rx_apb_prdata;
    logic        rx_apb_pready;
 
    // -------------------------------------------------------------------------
    // Sideband configuration (written by driver)
    // -------------------------------------------------------------------------
    logic [2:0] cfg_active_lanes = 3'd4;
    logic [5:0] cfg_rx_data_type = 6'h2A;
 
    // -------------------------------------------------------------------------
    // Status flags (driven from DUT, read by rx_monitor / scoreboard)
    // -------------------------------------------------------------------------
    logic rx_crc_ok;
    logic rx_crc_done;
    logic rx_ecc_single;
    logic rx_ecc_double;
 
    // -------------------------------------------------------------------------
    // Resets (read by monitors)
    // -------------------------------------------------------------------------
    logic sys_rst_n;
    logic preset_n;
    logic pixel_rst_n;
    logic byte_rst_n;
 
endinterface : csi_rx_if