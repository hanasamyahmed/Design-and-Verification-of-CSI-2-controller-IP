// =============================================================================
// File        : csi_rx_monitor.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Monitor for the RX output agent (passive agent side).
//               Samples the AXI-Stream pixel output from the DUT and the
//               CRC/ECC status lines.  Publishes to two analysis ports:
//                 mon_ap  – pixel stream (sent to scoreboard as "actual")
//                 stat_ap – CRC/ECC status events (sent to scoreboard)
// =============================================================================

package csi_rx_monitor_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;

    // -------------------------------------------------------------------------
    // Separate status item so the scoreboard can track integrity events
    // -------------------------------------------------------------------------
    class csi_rx_status_item extends uvm_object;
        `uvm_object_utils(csi_rx_status_item)

        logic rx_crc_ok;
        logic rx_crc_done;
        logic rx_ecc_single;
        logic rx_ecc_double;
        time  timestamp;

        function new(string name = "csi_rx_status_item");
            super.new(name);
        endfunction : new

        function string convert2string();
            return $sformatf(
                "t=%0t CRC_done=%b CRC_ok=%b ECC_single=%b ECC_double=%b",
                timestamp, rx_crc_done, rx_crc_ok, rx_ecc_single, rx_ecc_double
            );
        endfunction : convert2string
    endclass : csi_rx_status_item

    // -------------------------------------------------------------------------
    // RX Monitor
    // -------------------------------------------------------------------------
    class csi_rx_monitor extends uvm_monitor;
        `uvm_component_utils(csi_rx_monitor)

        virtual csi_rx_if rx_vif;

        uvm_analysis_port #(csi_seq_item)         mon_ap;   // pixel data stream
        uvm_analysis_port #(csi_rx_status_item)   stat_ap;  // CRC / ECC events

        function new(string name = "csi_rx_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon_ap  = new("mon_ap",  this);
            stat_ap = new("stat_ap", this);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // run_phase – two parallel threads: pixel stream + status events
        // -----------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            super.run_phase(phase);
            // Keep tready asserted so the DUT is never stalled
            rx_vif.rx_axis_tready <= 1'b1;

            fork
                monitor_pixel_stream();
                monitor_status_signals();
            join_none
        endtask : run_phase

        // -----------------------------------------------------------------------
        // Thread 1 – sample RX AXI-Stream on every valid+ready beat
        // -----------------------------------------------------------------------
        task monitor_pixel_stream();
            forever begin
                @(posedge rx_vif.pixel_clk);
                if (rx_vif.rx_axis_tvalid && rx_vif.rx_axis_tready) begin
                    csi_seq_item rx_item;
                    rx_item = csi_seq_item::type_id::create("rx_item");

                    rx_item.rx_data   = rx_vif.rx_axis_tdata;
                    rx_item.rx_tkeep  = rx_vif.rx_axis_tkeep;
                    rx_item.rx_tlast  = rx_vif.rx_axis_tlast;
                    rx_item.rx_tuser  = rx_vif.rx_axis_tuser;
                    rx_item.rx_tvalid = rx_vif.rx_axis_tvalid;

                    mon_ap.write(rx_item);
                    `uvm_info("csi_rx_monitor",
                        $sformatf("RX beat sampled: Data=0x%08X SOF=%b EOL=%b",
                            rx_item.rx_data, rx_item.rx_tuser, rx_item.rx_tlast),
                        UVM_HIGH)
                end
            end
        endtask : monitor_pixel_stream

        // -----------------------------------------------------------------------
        // Thread 2 – sample CRC/ECC status on byte_clk edges
        // -----------------------------------------------------------------------
        task monitor_status_signals();
            forever begin
                @(posedge rx_vif.byte_clk);
                if (rx_vif.rx_crc_done || rx_vif.rx_ecc_single || rx_vif.rx_ecc_double) begin
                    csi_rx_status_item stat;
                    stat = csi_rx_status_item::type_id::create("stat");

                    stat.rx_crc_ok     = rx_vif.rx_crc_ok;
                    stat.rx_crc_done   = rx_vif.rx_crc_done;
                    stat.rx_ecc_single = rx_vif.rx_ecc_single;
                    stat.rx_ecc_double = rx_vif.rx_ecc_double;
                    stat.timestamp     = $time;

                    stat_ap.write(stat);

                    if (rx_vif.rx_crc_done)
                        `uvm_info("csi_rx_monitor",
                            $sformatf("[CRC] done=%b ok=%b @%0t",
                                rx_vif.rx_crc_done, rx_vif.rx_crc_ok, $time),
                            UVM_MEDIUM)
                    if (rx_vif.rx_ecc_single)
                        `uvm_warning("csi_rx_monitor",
                            $sformatf("[ECC] Single-bit error corrected @%0t", $time))
                    if (rx_vif.rx_ecc_double)
                        `uvm_error("csi_rx_monitor",
                            $sformatf("[ECC] Double-bit error detected @%0t", $time))
                end
            end
        endtask : monitor_status_signals

    endclass : csi_rx_monitor

endpackage : csi_rx_monitor_pkg
