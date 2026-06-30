// =============================================================================
// File        : csi_tx_agent.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Active Agent for the TX pixel input side.
//               Contains sequencer, driver, and tx_monitor.
//               Publishes sampled TX transactions via agt_ap for the scoreboard.
// =============================================================================

package csi_tx_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;
    import csi_config_pkg::*;
    import csi_tx_sequencer_pkg::*;
    import csi_tx_driver_pkg::*;
    import csi_tx_monitor_pkg::*;

    class csi_tx_agent extends uvm_agent;
        `uvm_component_utils(csi_tx_agent)

        csi_tx_sequencer sqr;
        csi_tx_driver    drv;
        csi_tx_monitor   mon;
        csi_config       csi_cfg;

        uvm_analysis_port #(csi_seq_item) agt_ap;  // forwarded to scoreboard

        function new(string name = "csi_tx_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        // -----------------------------------------------------------------------
        // build_phase
        // -----------------------------------------------------------------------
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db #(csi_config)::get(this, "", "CSI_CFG", csi_cfg))
                `uvm_fatal("build_phase", "TX Agent: cannot get csi_config from config_db")

            // Always create monitor (needed even in passive mode for observability)
            mon    = csi_tx_monitor::type_id::create("mon", this);
            agt_ap = new("agt_ap", this);

            if (csi_cfg.tx_agent_is_active == UVM_ACTIVE) begin
                sqr = csi_tx_sequencer::type_id::create("sqr", this);
                drv = csi_tx_driver::type_id::create("drv",    this);
            end
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // connect_phase
        // -----------------------------------------------------------------------
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            mon.tx_vif = csi_cfg.tx_vif;
            mon.mon_ap.connect(agt_ap);

            if (csi_cfg.tx_agent_is_active == UVM_ACTIVE) begin
                drv.tx_vif = csi_cfg.tx_vif;
                drv.rx_vif = csi_cfg.rx_vif;   // driver also programs RX APB/I2C
                drv.seq_item_port.connect(sqr.seq_item_export);
            end
        endfunction : connect_phase

    endclass : csi_tx_agent

endpackage : csi_tx_agent_pkg
