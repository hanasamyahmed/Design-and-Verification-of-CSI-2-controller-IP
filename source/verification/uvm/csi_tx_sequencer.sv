// =============================================================================
// File        : csi_tx_sequencer.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Sequencer for the TX input agent.
//               Passes csi_seq_item objects from sequences to the TX driver.
// =============================================================================

package csi_tx_sequencer_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;

    class csi_tx_sequencer extends uvm_sequencer #(csi_seq_item);
        `uvm_component_utils(csi_tx_sequencer)

        function new(string name = "csi_tx_sequencer", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

    endclass : csi_tx_sequencer

endpackage : csi_tx_sequencer_pkg
