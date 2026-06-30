// =============================================================================
// File Name    : csi_sva.sv
// Author       : Hana Samy
// Date         : June 2026
// Description  : SystemVerilog Assertions for the CSI-2 TX→D-PHY→RX loopback.
//                Covers:
//                  1. AXI-Stream TX handshake stability (data must not change
//                     while tvalid is high and tready is low).
//                  2. tuser (SOF) must only assert on the very first beat of a
//                     new frame (i.e., after a tlast or at start).
//                  3. CRC result must be stable for at least one cycle after
//                     rx_crc_done pulses.
//                  4. ECC double-bit error must never occur during normal ops.
//                  5. RX tvalid must eventually be followed by tlast (liveness).
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
    // 1. AXI-Stream TX handshake stability 
    //    Data must remain stable when tvalid is high and tready is low.
    // -------------------------------------------------------------------------
    property tx_handshake_stability;
        @(posedge pixel_clk) disable iff (!sys_rst_n)
        (tx_axis_tvalid && !tx_axis_tready) |=> $stable(tx_axis_tdata);
    endproperty : tx_handshake_stability

    assert property (tx_handshake_stability)
        else $error("[SVA FAIL] TX AXI-Stream: Data changed while tvalid high and tready low");
    cover property (tx_handshake_stability);

    // -------------------------------------------------------------------------
    // 2. tuser (SOF) must only assert on the very first beat of a new frame
    //    Tracking whether the previous beat was tlast or if it's the start after reset.
    // -------------------------------------------------------------------------
    logic frame_start;
    always_ff @(posedge pixel_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            frame_start <= 1'b1;
        end else if (tx_axis_tvalid && tx_axis_tready) begin
            frame_start <= tx_axis_tlast;
        end
    end

    property tx_sof_first_beat;
        @(posedge pixel_clk) disable iff (!sys_rst_n)
        tx_axis_tvalid && tx_axis_tready && tx_axis_tuser |-> frame_start;
    endproperty : tx_sof_first_beat

    assert property (tx_sof_first_beat)
        else $error("[SVA FAIL] TX AXI-Stream: tuser (SOF) asserted outside of frame start");
    cover property (tx_sof_first_beat);

    // -------------------------------------------------------------------------
    // 3. CRC result must be stable for at least one cycle after rx_crc_done pulses
    // -------------------------------------------------------------------------
    property crc_stable_after_done;
        @(posedge byte_clk) disable iff (!sys_rst_n)
        rx_crc_done |=> $stable(rx_crc_ok);
    endproperty : crc_stable_after_done

    assert property (crc_stable_after_done)
        else $error("[SVA FAIL] CRC check failed – rx_crc_ok not stable one cycle after rx_crc_done");
    cover property (crc_stable_after_done);

    // -------------------------------------------------------------------------
    // 4. ECC double-bit error must never occur during normal ops
    // -------------------------------------------------------------------------
    property no_ecc_double_error;
        @(posedge byte_clk) disable iff (!sys_rst_n)
        !rx_ecc_double;
    endproperty : no_ecc_double_error

    assert property (no_ecc_double_error)
        else $error("[SVA FAIL] ECC double-bit error detected on RX");
    cover property (no_ecc_double_error);

    // -------------------------------------------------------------------------
    // 5. RX tvalid eventually followed by tlast (liveness, max 4096 cycles)
    // -------------------------------------------------------------------------
    property rx_stream_terminates;
        @(posedge pixel_clk) disable iff (!sys_rst_n)
        (rx_axis_tvalid && rx_axis_tuser) |-> ##[1:4096] rx_axis_tlast;
    endproperty : rx_stream_terminates

    assert property (rx_stream_terminates)
        else $error("[SVA FAIL] RX stream started but tlast not seen within 4096 cycles");
    cover property (rx_stream_terminates);

endmodule : csi_sva