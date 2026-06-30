// =============================================================================
// File        : csi_config.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Configuration object for the CSI-2 loopback environment.
//               Holds virtual interface handles and active/passive settings.
// =============================================================================

package csi_config_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class csi_config extends uvm_object;
        `uvm_object_utils(csi_config)

        // -------------------------------------------------------------------------
        // Virtual interface handles
        // -------------------------------------------------------------------------
        virtual csi_tx_if tx_vif;   // TX pixel input interface
        virtual csi_rx_if rx_vif;   // RX pixel output interface

        // -------------------------------------------------------------------------
        // Agent roles
        // -------------------------------------------------------------------------
        uvm_active_passive_enum tx_agent_is_active = UVM_ACTIVE;   // TX drives stimulus
        uvm_active_passive_enum rx_agent_is_active = UVM_PASSIVE;  // RX only observes

        // -------------------------------------------------------------------------
        // Scenario parameters  (propagated to sequences)
        // -------------------------------------------------------------------------
        int unsigned num_pixels_per_line = 1000;
        int unsigned num_lines_per_frame = 100;
        int unsigned num_frames          = 10;

        // Default CSI-2 settings
        logic [5:0]  cfg_data_type     = 6'h2A; // RAW8
        logic [2:0]  cfg_active_lanes  = 3'd4;
        logic        cfg_crc_en        = 1'b1;
        logic        cfg_scram_en      = 1'b1;

        // -------------------------------------------------------------------------
        // Constructor
        // -------------------------------------------------------------------------
        function new(string name = "csi_config");
            super.new(name);
        endfunction : new

    endclass : csi_config

endpackage : csi_config_pkg
