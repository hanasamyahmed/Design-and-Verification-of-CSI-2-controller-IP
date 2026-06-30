// =============================================================================
// File        : csi_rx_agent.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Passive Agent for the RX pixel output side.
//               Contains only an rx_monitor – no driver or sequencer needed
//               since the RX side is purely observed.
//               Publishes via agt_ap (pixel stream) and stat_ap (CRC/ECC).
// =============================================================================

package csi_rx_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;
    import csi_config_pkg::*;
    import csi_rx_monitor_pkg::*;

    class csi_rx_agent extends uvm_agent;
        `uvm_component_utils(csi_rx_agent)

        csi_rx_monitor  mon;
        csi_config      csi_cfg;

        uvm_analysis_port #(csi_seq_item)         agt_ap;   // pixel stream
        uvm_analysis_port #(csi_rx_status_item)   stat_ap;  // CRC / ECC events

        function new(string name = "csi_rx_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        // -----------------------------------------------------------------------
        // build_phase
        // -----------------------------------------------------------------------
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db #(csi_config)::get(this, "", "CSI_CFG", csi_cfg))
                `uvm_fatal("build_phase", "RX Agent: cannot get csi_config from config_db")

            mon     = csi_rx_monitor::type_id::create("mon", this);
            agt_ap  = new("agt_ap",  this);
            stat_ap = new("stat_ap", this);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // connect_phase
        // -----------------------------------------------------------------------
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            mon.rx_vif = csi_cfg.rx_vif;
            mon.mon_ap.connect(agt_ap);
            mon.stat_ap.connect(stat_ap);
        endfunction : connect_phase

    endclass : csi_rx_agent

endpackage : csi_rx_agent_pkg
