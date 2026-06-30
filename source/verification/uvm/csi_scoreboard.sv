// =============================================================================
// File        : csi_scoreboard.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Scoreboard for the CSI-2 loopback environment.
//               Receives:
//                 expected_in  – TX monitor stream  (what was sent into DUT)
//                 actual_in    – RX monitor stream  (what came out of DUT)
//                 status_in    – CRC/ECC events     (from RX monitor stat_ap)
//
//               Comparison strategy:
//                 Each accepted TX AXI-Stream beat goes into an ordered queue.
//                 Each received RX AXI-Stream beat is compared against the
//                 head of the queue (pixel_data vs rx_data, tuser vs rx_tuser,
//                 tlast vs rx_tlast).
//               CRC check: every CRC event must report rx_crc_ok == 1.
//               ECC check: double-bit ECC errors increment error counter.
// =============================================================================

package csi_scoreboard_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;
    import csi_rx_monitor_pkg::*;

    class csi_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(csi_scoreboard)

        // -----------------------------------------------------------------------
        // Analysis exports  (connected from environment)
        // -----------------------------------------------------------------------
        uvm_analysis_export #(csi_seq_item)         expected_export;  // from TX mon
        uvm_analysis_export #(csi_seq_item)         actual_export;    // from RX mon
        uvm_analysis_export #(csi_rx_status_item)   status_export;    // CRC/ECC

        // -----------------------------------------------------------------------
        // Internal FIFOs
        // -----------------------------------------------------------------------
        uvm_tlm_analysis_fifo #(csi_seq_item)         expected_fifo;
        uvm_tlm_analysis_fifo #(csi_seq_item)         actual_fifo;
        uvm_tlm_analysis_fifo #(csi_rx_status_item)   status_fifo;

        // -----------------------------------------------------------------------
        // Counters
        // -----------------------------------------------------------------------
        int unsigned correct_count  = 0;
        int unsigned error_count    = 0;
        int unsigned crc_pass_count = 0;
        int unsigned crc_fail_count = 0;
        int unsigned ecc_single_cnt = 0;
        int unsigned ecc_double_cnt = 0;

        function new(string name = "csi_scoreboard", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        // -----------------------------------------------------------------------
        // build_phase
        // -----------------------------------------------------------------------
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            expected_export = new("expected_export", this);
            actual_export   = new("actual_export",   this);
            status_export   = new("status_export",   this);

            expected_fifo = new("expected_fifo", this);
            actual_fifo   = new("actual_fifo",   this);
            status_fifo   = new("status_fifo",   this);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // connect_phase  – wire exports to FIFOs
        // -----------------------------------------------------------------------
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            expected_export.connect(expected_fifo.analysis_export);
            actual_export.connect(actual_fifo.analysis_export);
            status_export.connect(status_fifo.analysis_export);
        endfunction : connect_phase

        // -----------------------------------------------------------------------
        // run_phase  – three parallel comparison threads
        // -----------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            super.run_phase(phase);
            fork
                compare_pixel_stream();
                check_crc_ecc_status();
            join_none
        endtask : run_phase

        // -----------------------------------------------------------------------
        // Thread 1: pixel-by-pixel comparison
        // -----------------------------------------------------------------------
        task compare_pixel_stream();
            csi_seq_item expected_item, actual_item;
            forever begin
                expected_fifo.get(expected_item);
                actual_fifo.get(actual_item);

                // Compare payload, SOF, and EOL
                if ( (expected_item.pixel_data !== actual_item.rx_data) ||
                     (expected_item.tuser       !== actual_item.rx_tuser) ||
                     (expected_item.tlast        !== actual_item.rx_tlast) ) begin

                    `uvm_fatal("csi_scoreboard",
                        $sformatf("PIXEL MISMATCH!\n  TX: Data=0x%08X SOF=%b EOL=%b\n  RX: Data=0x%08X SOF=%b EOL=%b",
                            expected_item.pixel_data, expected_item.tuser, expected_item.tlast,
                            actual_item.rx_data,      actual_item.rx_tuser, actual_item.rx_tlast))
                    error_count++;
                end else begin
                    `uvm_info("csi_scoreboard",
                        $sformatf("[PASS] Pixel match: 0x%08X SOF=%b EOL=%b",
                            expected_item.pixel_data, expected_item.tuser, expected_item.tlast),
                        UVM_HIGH)
                    correct_count++;
                end
            end
        endtask : compare_pixel_stream

        // -----------------------------------------------------------------------
        // Thread 2: CRC / ECC integrity checks
        // -----------------------------------------------------------------------
        task check_crc_ecc_status();
            csi_rx_status_item stat;
            forever begin
                status_fifo.get(stat);

                if (stat.rx_crc_done) begin
                    if (stat.rx_crc_ok) begin
                        `uvm_info("csi_scoreboard",
                            $sformatf("[CRC PASS] @%0t", stat.timestamp), UVM_MEDIUM)
                        crc_pass_count++;
                    end else begin
                        `uvm_error("csi_scoreboard",
                            $sformatf("[CRC FAIL] CRC check failed @%0t", stat.timestamp))
                        crc_fail_count++;
                        error_count++;
                    end
                end

                if (stat.rx_ecc_single) begin
                    `uvm_warning("csi_scoreboard",
                        $sformatf("[ECC CORRECTED] single-bit ECC error @%0t", stat.timestamp))
                    ecc_single_cnt++;
                end

                if (stat.rx_ecc_double) begin
                    `uvm_error("csi_scoreboard",
                        $sformatf("[ECC DOUBLE ERROR] uncorrectable ECC @%0t", stat.timestamp))
                    ecc_double_cnt++;
                    error_count++;
                end
            end
        endtask : check_crc_ecc_status

        // -----------------------------------------------------------------------
        // report_phase
        // -----------------------------------------------------------------------
        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("csi_scoreboard",
                $sformatf("\n=========================================\n  SCOREBOARD REPORT\n=========================================\n  Pixel matches  : %0d\n  Pixel errors   : %0d\n  CRC passed     : %0d\n  CRC failed     : %0d\n  ECC corrected  : %0d\n  ECC double err : %0d\n=========================================",
                    correct_count, error_count,
                    crc_pass_count, crc_fail_count,
                    ecc_single_cnt, ecc_double_cnt),
                UVM_MEDIUM)

            if (error_count == 0)
                `uvm_info("csi_scoreboard", ">>> [PASS] All transactions verified end-to-end ✔ <<<", UVM_NONE)
            else
                `uvm_error("csi_scoreboard",
                    $sformatf(">>> [FAIL] %0d error(s) detected <<<", error_count))
        endfunction : report_phase

    endclass : csi_scoreboard

endpackage : csi_scoreboard_pkg
