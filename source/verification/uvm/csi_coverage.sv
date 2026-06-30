// =============================================================================
// File        : csi_coverage.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Coverage Collector for the CSI-2 loopback environment.
//               Tracks:
//                 - Lane configuration coverage (1 / 2 / 4 lanes)
//                 - Data type coverage (RAW8 / RAW10)
//                 - SOF / EOL toggling
//                 - CRC / scrambler enable combinations
//                 - CRC pass/fail events
//                 - ECC single and double bit error events
// =============================================================================

package csi_coverage_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;
    import csi_rx_monitor_pkg::*;

    class csi_coverage extends uvm_component;
        `uvm_component_utils(csi_coverage)

        // -----------------------------------------------------------------------
        // Analysis exports (connected from environment)
        // -----------------------------------------------------------------------
        uvm_analysis_export #(csi_seq_item)         cov_export;      // TX stream
        uvm_analysis_export #(csi_rx_status_item)   stat_cov_export; // CRC/ECC

        uvm_tlm_analysis_fifo #(csi_seq_item)         cov_fifo;
        uvm_tlm_analysis_fifo #(csi_rx_status_item)   stat_cov_fifo;

        // -----------------------------------------------------------------------
        // Sample variables
        // -----------------------------------------------------------------------
        csi_seq_item        seq_item_cov;
        csi_rx_status_item  stat_item_cov;

        // -----------------------------------------------------------------------
        // Covergroups
        // -----------------------------------------------------------------------

        // Lane configuration
        covergroup lane_config_cg;
            cp_lanes : coverpoint seq_item_cov.cfg_active_lanes {
                bins lane1 = {3'd1};
                bins lane2 = {3'd2};
                bins lane4 = {3'd4};
            }
        endgroup : lane_config_cg

        // Data type
        covergroup data_type_cg;
            cp_dt : coverpoint seq_item_cov.cfg_data_type {
                bins raw8  = {6'h2A};
                bins raw10 = {6'h2B};
            }
        endgroup : data_type_cg

        // Frame control markers
        covergroup frame_ctrl_cg;
            cp_sof : coverpoint seq_item_cov.tuser {
                bins sof     = {1'b1};
                bins no_sof  = {1'b0};
            }
            cp_eol : coverpoint seq_item_cov.tlast {
                bins eol     = {1'b1};
                bins no_eol  = {1'b0};
            }
            cx_sof_eol : cross cp_sof, cp_eol{
     
                 ignore_bins impossible_1_pixel_frame = binsof(cp_sof.sof) && binsof(cp_eol.eol);
            }

        endgroup : frame_ctrl_cg

        // CRC / scrambler enable combinations
        covergroup features_cg;
            cp_crc   : coverpoint seq_item_cov.cfg_crc_en   { bins on = {1}; bins off = {0}; }
            cp_scram  : coverpoint seq_item_cov.cfg_scram_en { bins on = {1}; bins off = {0}; }
            cx_feat  : cross cp_crc, cp_scram;
        endgroup : features_cg

       // CRC/ECC integrity events (Happy Path Only)
        covergroup integrity_cg;
            cp_crc_result : coverpoint stat_item_cov.rx_crc_ok {
                bins crc_pass = {1'b1};
                ignore_bins crc_fail = {1'b0}; // We do not inject CRC errors
            }
            
            cp_ecc_single : coverpoint stat_item_cov.rx_ecc_single {
                bins no_ecc_single = {1'b0};   // Expecting NO single-bit errors
                ignore_bins ecc_corrected = {1'b1}; 
            }
            
            cp_ecc_double : coverpoint stat_item_cov.rx_ecc_double {
                bins no_ecc_double = {1'b0};   // Expecting NO double-bit errors
                ignore_bins ecc_error = {1'b1};
            }
        endgroup : integrity_cg
        // -----------------------------------------------------------------------
        // Constructor
        // -----------------------------------------------------------------------
        function new(string name = "csi_coverage", uvm_component parent = null);
            super.new(name, parent);
            lane_config_cg  = new();
            data_type_cg    = new();
            frame_ctrl_cg   = new();
            features_cg     = new();
            integrity_cg    = new();
        endfunction : new

        // -----------------------------------------------------------------------
        // build_phase
        // -----------------------------------------------------------------------
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cov_export      = new("cov_export",      this);
            stat_cov_export = new("stat_cov_export", this);
            cov_fifo        = new("cov_fifo",        this);
            stat_cov_fifo   = new("stat_cov_fifo",   this);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // connect_phase
        // -----------------------------------------------------------------------
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            cov_export.connect(cov_fifo.analysis_export);
            stat_cov_export.connect(stat_cov_fifo.analysis_export);
        endfunction : connect_phase

        // -----------------------------------------------------------------------
        // run_phase – sample covergroups from both FIFOs
        // -----------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            super.run_phase(phase);
            fork
                // Pixel stream coverage
                forever begin
                    cov_fifo.get(seq_item_cov);
                    lane_config_cg.sample();
                    data_type_cg.sample();
                    frame_ctrl_cg.sample();
                    features_cg.sample();
                end
                // Status event coverage
                forever begin
                    stat_cov_fifo.get(stat_item_cov);
                    if (stat_item_cov.rx_crc_done)
                        integrity_cg.sample();
                end
            join_none
        endtask : run_phase

    endclass : csi_coverage

endpackage : csi_coverage_pkg
