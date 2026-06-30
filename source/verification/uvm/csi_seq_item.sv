// =============================================================================
// File        : csi_seq_item.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Sequence Item for the CSI-2 TX/RX loopback environment.
//               Represents one AXI-Stream pixel transaction driven into the TX.
// =============================================================================

package csi_seq_item_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class csi_seq_item extends uvm_sequence_item;
        `uvm_object_utils(csi_seq_item)

        // -------------------------------------------------------------------------
        // Stimulus Fields (driven by driver onto TX AXI-Stream interface)
        // -------------------------------------------------------------------------
        rand logic [31:0] pixel_data;    // AXI tdata  – pixel payload (RAW8/RAW10)
        rand logic        tuser;         // AXI tuser  – Start-of-Frame marker
        rand logic        tlast;         // AXI tlast  – End-of-Line marker
        rand logic        tvalid;        // AXI tvalid

        // -------------------------------------------------------------------------
        // Response / Observed Fields (captured by monitors)
        // -------------------------------------------------------------------------
        logic        tready;            // TX side back-pressure
        logic [31:0] rx_data;           // RX AXI tdata  received from DUT
        logic [3:0]  rx_tkeep;          // RX AXI tkeep
        logic        rx_tlast;          // RX AXI tlast
        logic        rx_tuser;          // RX AXI tuser  (SOF on RX side)
        logic        rx_tvalid;         // RX AXI tvalid

        // -------------------------------------------------------------------------
        // Frame / Line Context  (filled by sequence, used by scoreboard)
        // -------------------------------------------------------------------------
        int unsigned  frame_id;         // Which frame this pixel belongs to
        int unsigned  line_id;          // Which line inside the frame
        int unsigned  pixel_id;         // Pixel index inside the line

        // -------------------------------------------------------------------------
        // APB / I2C Configuration carried with first transaction of a scenario
        // -------------------------------------------------------------------------
        rand logic [2:0] cfg_active_lanes; // 1, 2, or 4 lanes
        rand logic [5:0] cfg_data_type;    // CSI-2 data type (default 6'h2A = RAW8)
        rand logic       cfg_crc_en;       // CRC enable
        rand logic       cfg_scram_en;     // Scrambler enable

        // -------------------------------------------------------------------------
        // Constraints
        // -------------------------------------------------------------------------
        constraint data_type_c {
            cfg_data_type inside {6'h2A, 6'h2B, 6'h1E, 6'h22, 6'h24}; 
        }

        constraint lanes_c {
            cfg_active_lanes inside {3'd1, 3'd2, 3'd4};
        }

        constraint crc_scram_default_c {
        soft cfg_crc_en == 1'b1;
        soft cfg_scram_en == 1'b1;
    }

        constraint tvalid_high_c {
            tvalid == 1'b1; // Driver always drives valid data
        }

        // -------------------------------------------------------------------------
        // Constructor
        // -------------------------------------------------------------------------
        function new(string name = "csi_seq_item");
            super.new(name);
        endfunction : new

        // -------------------------------------------------------------------------
        // Utility
        // -------------------------------------------------------------------------
        function string convert2string();
            return $sformatf(
                "%s | Frame=%0d Line=%0d Pix=%0d | TX_Data=0x%08X SOF=%b EOL=%b | RX_Data=0x%08X rx_sof=%b rx_eol=%b | Lanes=%0d DT=0x%02X CRC=%b SCR=%b",
                super.convert2string(),
                frame_id, line_id, pixel_id,
                pixel_data, tuser, tlast,
                rx_data, rx_tuser, rx_tlast,
                cfg_active_lanes, cfg_data_type,
                cfg_crc_en, cfg_scram_en
            );
        endfunction : convert2string

        function string convert2string_stimulus();
            return $sformatf(
                "TX: Data=0x%08X SOF=%b EOL=%b valid=%b | Cfg: Lanes=%0d DT=0x%02X",
                pixel_data, tuser, tlast, tvalid,
                cfg_active_lanes, cfg_data_type
            );
        endfunction : convert2string_stimulus

    endclass : csi_seq_item

endpackage : csi_seq_item_pkg
