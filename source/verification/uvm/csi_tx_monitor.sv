// =============================================================================
// File        : csi_tx_monitor.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Monitor for the TX input agent (active agent side).
//               Samples the AXI-Stream pixel input presented to the DUT and
//               records each accepted transaction into the analysis port.
//               The scoreboard uses these as the "expected" reference stream.
// =============================================================================

package csi_tx_monitor_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;

    class csi_tx_monitor extends uvm_monitor;
        `uvm_component_utils(csi_tx_monitor)

        virtual csi_tx_if tx_vif;

        uvm_analysis_port #(csi_seq_item) mon_ap;

        function new(string name = "csi_tx_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon_ap = new("mon_ap", this);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // run_phase – sample on positive pixel_clk edge whenever tvalid & tready
        // -----------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            super.run_phase(phase);
            forever begin
                csi_seq_item tx_item;
                @(posedge tx_vif.pixel_clk);

                // Capture only accepted beats (handshake complete)
                if (tx_vif.tx_axis_tvalid && tx_vif.tx_axis_tready) begin
                    tx_item = csi_seq_item::type_id::create("tx_item");

                    tx_item.pixel_data = tx_vif.tx_axis_tdata;
                    tx_item.tvalid     = tx_vif.tx_axis_tvalid;
                    tx_item.tuser      = tx_vif.tx_axis_tuser;
                    tx_item.tlast      = tx_vif.tx_axis_tlast;
                    tx_item.tready     = tx_vif.tx_axis_tready;

                    // ---> ADD THESE LINES SO COVERAGE CAN SEE THE CONFIG <---
                    tx_item.cfg_active_lanes = tx_vif.cfg_active_lanes;
                    tx_item.cfg_data_type    = tx_vif.cfg_rx_data_type;
                    tx_item.cfg_crc_en       = tx_vif.cfg_crc_en;
                    tx_item.cfg_scram_en     = tx_vif.cfg_scram_en;

                    mon_ap.write(tx_item);
                    `uvm_info("csi_tx_monitor",
                        $sformatf("TX beat sampled: Data=0x%08X SOF=%b EOL=%b",
                            tx_item.pixel_data, tx_item.tuser, tx_item.tlast),
                        UVM_HIGH)
                end
            end
        endtask : run_phase

    endclass : csi_tx_monitor

endpackage : csi_tx_monitor_pkg
