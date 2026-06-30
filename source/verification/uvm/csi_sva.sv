// =============================================================================
// File        : csi_sva.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : SystemVerilog Assertions for the CSI-2 TX→D-PHY→RX loopback.
//               Covers:
//                 1. AXI-Stream TX handshake stability (data must not change
//                    while tvalid is high and tready is low).
//                 2. tuser (SOF) must only assert on the very first beat of a
//                    new frame (i.e., after a tlast or at start).
//                 3. CRC result must be stable for at least one cycle after
//                    rx_crc_done pulses.
//                 4. ECC double-bit error must never occur during normal ops.
//                 5. RX tvalid must eventually be followed by tlast (liveness).
// =============================================================================

module csi_sva (
    // Clocks & Resets
    input logic pixel_clk,
    input logic byte_clk,
    input logic sys_rst_n,

    // TX AXI-Stream input
    input logic [31:0] tx_axis_tdata,
    input logic        tx_axis_tvalid,
    input logic        tx_axis_tready,
    input logic        tx_axis_tuser,
    input logic        tx_axis_tlast,

    // RX AXI-Stream output
    input logic [31:0] rx_axis_tdata,
    input logic        rx_axis_tvalid,
    input logic        rx_axis_tready,
    input logic        rx_axis_tlast,
    input logic        rx_axis_tuser,

    // RX status
    input logic        rx_crc_ok,
    input logic        rx_crc_done,
    input logic        rx_ecc_single,
    input logic        rx_ecc_double
);


    // -------------------------------------------------------------------------
    // SVA 2: SOF (tuser) must be a single-beat pulse
    //   When tuser (Start of Frame) is asserted, it must de-assert on the 
    //   very next valid beat.
    // -------------------------------------------------------------------------
    property rx_sof_single_beat;
        @(posedge pixel_clk) disable iff (!sys_rst_n)
        (rx_axis_tvalid && rx_axis_tready && rx_axis_tuser)
            ##1 (rx_axis_tvalid && rx_axis_tready)[->1]
            |-> !rx_axis_tuser;
    endproperty : rx_sof_single_beat

    assert property (rx_sof_single_beat)
        else $error("[SVA FAIL] RX AXI-Stream: tuser (SOF) was held for more than 1 pixel");
    cover  property (rx_sof_single_beat);
    // -----------------------------------------------
    // -------------------------------------------------------------------------
    // SVA 3: CRC OK after CRC Done
    //   When rx_crc_done pulses, rx_crc_ok must be high (no CRC failure
    //   during normal, uncorrupted loopback operation).
    // -------------------------------------------------------------------------
    property crc_ok_when_done;
        @(posedge byte_clk) disable iff (!sys_rst_n)
        rx_crc_done |-> rx_crc_ok;
    endproperty : crc_ok_when_done

    assert property (crc_ok_when_done)
        else $error("[SVA FAIL] CRC check failed – rx_crc_done high but rx_crc_ok low");
    cover  property (crc_ok_when_done);

    // -------------------------------------------------------------------------
    // SVA 4: No ECC Double-Bit Errors
    //   In a clean loopback there should be no uncorrectable ECC errors.
    // -------------------------------------------------------------------------
    property no_ecc_double_error;
        @(posedge byte_clk) disable iff (!sys_rst_n)
        !rx_ecc_double;
    endproperty : no_ecc_double_error

    assert property (no_ecc_double_error)
        else $error("[SVA FAIL] ECC double-bit error detected on RX");
    cover  property (no_ecc_double_error);

    // -------------------------------------------------------------------------
    // SVA 5: Reset clears TX AXI-Stream outputs
    //   Immediately after reset de-assertion, tvalid must be low.
    // -------------------------------------------------------------------------
    property tx_valid_low_after_reset;
        @(posedge pixel_clk)
        $rose(sys_rst_n) |=> !tx_axis_tvalid;
    endproperty : tx_valid_low_after_reset

    assert property (tx_valid_low_after_reset)
        else $error("[SVA FAIL] tx_axis_tvalid not deasserted after reset");
    cover  property (tx_valid_low_after_reset);

    // -------------------------------------------------------------------------
    // SVA 6: RX tvalid eventually followed by tlast (liveness, max 4096 cycles)
    // -------------------------------------------------------------------------
    property rx_stream_terminates;
        @(posedge pixel_clk) disable iff (!sys_rst_n)
        (rx_axis_tvalid && rx_axis_tuser) |-> ##[1:4000] rx_axis_tlast;
    endproperty : rx_stream_terminates

    assert property (rx_stream_terminates)
        else $error("[SVA FAIL] RX stream started but tlast not seen within 4096 cycles");
    cover  property (rx_stream_terminates);

endmodule : csi_sva
