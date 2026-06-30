// =============================================================================
// Package Name   : csi_coverage_pkg
// File Name      : csi_coverage_pkg.sv
// Author         : Hana Samy
// Date           : June 2026
// Description    : Functional coverage package for MIPI CSI-2 / AXI-Stream 
//                  Bridge. Contains covergroups for active lanes, data types, 
//                  frame control markers (SOF/EOL), configuration features, 
//                  and link integrity metrics.
// =============================================================================

package csi_coverage_pkg;

    class csi_coverage;
        // Variables to hold sampled data
        logic [2:0] cfg_active_lanes;
        logic [5:0] cfg_data_type;
        logic       tuser;
        logic       tlast;
        logic       cfg_crc_en;
        logic       cfg_scram_en;
        logic       rx_crc_ok;
        logic       rx_ecc_single;
        logic       rx_ecc_double;

        // -----------------------------------------------------------------------
        // Covergroups
        // -----------------------------------------------------------------------
        
        // Covers active MIPI D-PHY lane configurations (1, 2, or 4 lanes)
        covergroup lane_config_cg;
            cp_lanes : coverpoint cfg_active_lanes {
                bins lane1 = {3'd1};
                bins lane2 = {3'd2};
                bins lane4 = {3'd4};
            }
        endgroup

        // Covers MIPI CSI-2 data types processed by the bridge
        covergroup data_type_cg;
            cp_dt : coverpoint cfg_data_type {
                bins raw8   = {6'h2A};
                bins raw10  = {6'h2B};
                bins yuv422 = {6'h1E};
                bins rgb565 = {6'h22};
                bins rgb888 = {6'h24};
            }
        endgroup

        // Frame control markers (SOF/EOL are mutually exclusive in this TB)
        covergroup frame_ctrl_cg;
            cp_sof : coverpoint tuser { bins sof = {1}; bins no_sof = {0}; }
            cp_eol : coverpoint tlast { bins eol = {1}; bins no_eol = {0}; }
            cx_sof_eol : cross cp_sof, cp_eol {
                // SOF (tuser) and EOL (tlast) cannot assert simultaneously per beat
                ignore_bins mutually_exclusive = binsof(cp_sof.sof) && binsof(cp_eol.eol);
            }
        endgroup

        // Feature combinations (CRC and Scrambler ON/OFF states)
        covergroup features_cg;
            cp_crc   : coverpoint cfg_crc_en   { 
                bins on  = {1}; 
                bins off = {0}; 
            }
            cp_scram : coverpoint cfg_scram_en { 
                bins on  = {1}; 
                bins off = {0}; 
            }
            cx_feat  : cross cp_crc, cp_scram;
        endgroup

        // Link Integrity metrics (Ideal verification environment tracks zero/passed errors)
        covergroup integrity_cg;
            cp_crc_result : coverpoint rx_crc_ok    { bins crc_pass = {1}; }
            cp_ecc_single : coverpoint rx_ecc_single { bins no_err = {0}; }
            cp_ecc_double : coverpoint rx_ecc_double { bins no_err = {0}; }
        endgroup

        // -----------------------------------------------------------------------
        // Constructor
        // -----------------------------------------------------------------------
        function new();
            lane_config_cg = new();
            data_type_cg   = new();
            frame_ctrl_cg  = new();
            features_cg    = new();
            integrity_cg   = new();
        endfunction

        // -----------------------------------------------------------------------
        // Sampling Methods
        // -----------------------------------------------------------------------
        
        // Sample TX interface metrics during active transfers
        function void sample_tx(logic [2:0] lanes, logic [5:0] dt, logic sof, logic eol, logic crc_en, logic scram_en);
            this.cfg_active_lanes = lanes;
            this.cfg_data_type    = dt;
            this.tuser            = sof;
            this.tlast            = eol;
            this.cfg_crc_en       = crc_en;
            this.cfg_scram_en     = scram_en;
            
            lane_config_cg.sample();
            data_type_cg.sample();
            frame_ctrl_cg.sample();
            features_cg.sample();
        endfunction

        // Sample RX status metrics from packet processing
        function void sample_rx_status(logic crc_ok, logic ecc_single, logic ecc_double);
            this.rx_crc_ok     = crc_ok;
            this.rx_ecc_single = ecc_single;
            this.rx_ecc_double = ecc_double;
            
            integrity_cg.sample();
        endfunction

    endclass

endpackage