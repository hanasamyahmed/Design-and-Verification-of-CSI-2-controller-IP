// =============================================================================
// File        : csi_top_env.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : Top-level UVM Environment for the CSI-2 loopback system.
//               Instantiates:
//                 tx_input_agent   (active)  – drives pixel data into TX
//                 rx_output_agent  (passive) – observes pixel data from RX
//                 csi_scoreboard             – compares expected vs actual
//                 csi_coverage               – functional coverage collection
//
//               Analysis connections (matches the architecture diagram):
//                 tx_input_agent.agt_ap  --> scoreboard.expected_export
//                 tx_input_agent.agt_ap  --> coverage.cov_export
//                 rx_output_agent.agt_ap --> scoreboard.actual_export
//                 rx_output_agent.stat_ap--> scoreboard.status_export
//                 rx_output_agent.stat_ap--> coverage.stat_cov_export
// =============================================================================

package csi_top_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;
    import csi_config_pkg::*;
    import csi_tx_agent_pkg::*;
    import csi_rx_agent_pkg::*;
    import csi_scoreboard_pkg::*;
    import csi_coverage_pkg::*;

    class csi_top_env extends uvm_env;
        `uvm_component_utils(csi_top_env)

        // -----------------------------------------------------------------------
        // Sub-components  (names match the architecture diagram)
        // -----------------------------------------------------------------------
        csi_tx_agent    tx_input_agent;
        csi_rx_agent    rx_output_agent;
        csi_scoreboard  sb;
        csi_coverage    cov;

        function new(string name = "csi_top_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        // -----------------------------------------------------------------------
        // build_phase
        // -----------------------------------------------------------------------
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            tx_input_agent  = csi_tx_agent::type_id::create("tx_input_agent",  this);
            rx_output_agent = csi_rx_agent::type_id::create("rx_output_agent", this);
            sb              = csi_scoreboard::type_id::create("sb",             this);
            cov             = csi_coverage::type_id::create("cov",              this);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // connect_phase  – wire analysis ports exactly as shown in the diagram
        // -----------------------------------------------------------------------
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            // TX agent feeds scoreboard (expected_in) and coverage
            tx_input_agent.agt_ap.connect(sb.expected_export);
            tx_input_agent.agt_ap.connect(cov.cov_export);

            // RX agent feeds scoreboard (actual_in) and coverage
            rx_output_agent.agt_ap.connect(sb.actual_export);
            rx_output_agent.stat_ap.connect(sb.status_export);
            rx_output_agent.stat_ap.connect(cov.stat_cov_export);
        endfunction : connect_phase

    endclass : csi_top_env

endpackage : csi_top_env_pkg
