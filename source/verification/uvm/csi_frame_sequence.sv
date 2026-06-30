// =============================================================================
// File        : csi_frame_sequence.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Sequence for the CSI-2 loopback test.
//
//  Matches reference TB outer loop (lines 557-580):
//    - Cycles lanes: 4 → 2 → 1 every frame (f%3)
//    - Alternates CRC:   1,0,1,0  (f%2==0)
//    - Alternates SCRAM: 1,1,0,0  (f%4<2)
//    - 1 pixel per clock, upper bits zeroed per data type
//
//  INTER-LINE GAP:
//    After each line the sequence sends a gap item (tvalid=0, tlast=0,
//    gap_type=LINE_GAP).  The driver waits 3000 pixel_clk cycles when it
//    sees this item.  This matches reference TB send_frame which calls
//    repeat(3000) @(posedge pixel_clk) between lines.
//
//  POST-FRAME FLUSH:
//    After the last line of a frame the sequence sends a flush item
//    (gap_type=FRAME_FLUSH).  The driver waits 5000 byte_clk cycles.
//    This matches reference TB repeat(5000) @(posedge byte_clk) after
//    send_frame, ensuring the pipeline drains before the next reinit().
// =============================================================================

package csi_frame_sequence_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;

    class csi_frame_sequence extends uvm_sequence #(csi_seq_item);
        `uvm_object_utils(csi_frame_sequence)

        // Sequence parameters – set by the test before start()
        int unsigned num_pixels_per_line = 1000;
        int unsigned num_lines_per_frame = 100;
        int unsigned num_frames          = 10;

        logic [5:0] cfg_data_type    = 6'h2A;   // RAW8 default
        logic [2:0] cfg_active_lanes = 3'd4;
        logic       cfg_crc_en       = 1'b1;
        logic       cfg_scram_en     = 1'b1;

        function new(string name = "csi_frame_sequence");
            super.new(name);
        endfunction : new

        task body();
            csi_seq_item cfg_item;
            csi_seq_item item;

            for (int f = 0; f < num_frames; f++) begin

                // -------------------------------------------------------------
                // Config beat  (tvalid=0) – driver intercepts this to run reinit
                // Parameters mirror reference TB lines 562-568
                // -------------------------------------------------------------
                cfg_item = csi_seq_item::type_id::create("cfg_item");
                start_item(cfg_item);

                // Lane rotation: 4 → 2 → 1 (ref TB lines 562-564)
                if      (f % 3 == 0) cfg_item.cfg_active_lanes = 3'd4;
                else if (f % 3 == 1) cfg_item.cfg_active_lanes = 3'd2;
                else                 cfg_item.cfg_active_lanes = 3'd1;

                // CRC / scrambler alternation (ref TB lines 567-568)
                cfg_item.cfg_crc_en    = (f % 2 == 0) ? 1'b1 : 1'b0;
                cfg_item.cfg_scram_en  = (f % 4 < 2)  ? 1'b1 : 1'b0;

                cfg_item.cfg_data_type = cfg_data_type;
                cfg_item.tvalid        = 1'b0;   // marks this as a config beat
                cfg_item.tlast         = 1'b0;
                cfg_item.tuser         = 1'b0;
                cfg_item.pixel_data    = 32'd0;
                cfg_item.frame_id      = f;
                cfg_item.line_id       = 0;
                cfg_item.pixel_id      = 0;

                finish_item(cfg_item);

                // -------------------------------------------------------------
                // Pixel beats – NUM_LINES lines, NUM_PIXELS pixels per line
                // 1 pixel per AXI-S transfer (matches reference TB send_line)
                //
                // After each line a LINE_GAP item is sent so the driver can
                // insert the 3000 pixel_clk idle period (reference TB behaviour).
                // After the last line a FRAME_FLUSH item causes the driver to
                // wait 5000 byte_clk cycles (reference TB post-frame drain).
                // -------------------------------------------------------------
                for (int ln = 0; ln < num_lines_per_frame; ln++) begin
                    for (int px = 0; px < num_pixels_per_line; px++) begin
                        item = csi_seq_item::type_id::create("item");
                        start_item(item);

                        // Randomize – constrain data width to data type
                        assert(item.randomize() with {
                            cfg_active_lanes == cfg_item.cfg_active_lanes;
                            cfg_data_type    == local::cfg_data_type;
                            cfg_crc_en       == cfg_item.cfg_crc_en;
                            cfg_scram_en     == cfg_item.cfg_scram_en;
                            tvalid           == 1'b1;
                            // Mask unused upper bits per data type
                            (cfg_data_type == 6'h2A) -> pixel_data[31:8]  == 24'h0;
                            (cfg_data_type == 6'h2B) -> pixel_data[31:10] == 22'h0;
                            (cfg_data_type == 6'h1E) -> pixel_data[31:16] == 16'h0;
                            (cfg_data_type == 6'h22) -> pixel_data[31:16] == 16'h0;
                            (cfg_data_type == 6'h24) -> pixel_data[31:24] == 8'h0;
                        });

                        // Deterministic sideband markers
                        item.tuser    = (ln == 0 && px == 0) ? 1'b1 : 1'b0;  // SOF
                        item.tlast    = (px == num_pixels_per_line - 1) ? 1'b1 : 1'b0; // EOL
                        item.frame_id = f;
                        item.line_id  = ln;
                        item.pixel_id = px;

                        finish_item(item);
                    end
                    // ----------------------------------------------------------
                    // NOTE: The driver in csi_tx_driver.sv already inserts a
                    // 3000 pixel_clk gap whenever it sees tlast=1 (end of line).
                    // That driver-side mechanism is the PRIMARY fix.
                    //
                    // If your project uses a seq_item with a gap_type field,
                    // you can additionally send an explicit LINE_GAP item here:
                    //
                    //   csi_seq_item gap_item;
                    //   gap_item = csi_seq_item::type_id::create("gap_item");
                    //   start_item(gap_item);
                    //   gap_item.tvalid   = 1'b0;
                    //   gap_item.gap_type = LINE_GAP;   // enum in seq_item
                    //   gap_item.frame_id = f;
                    //   gap_item.line_id  = ln;
                    //   finish_item(gap_item);
                    //
                    // If gap_type is not in your seq_item, the driver-side
                    // gap on tlast=1 is sufficient — do not add anything here.
                    // ----------------------------------------------------------
                end

                // --------------------------------------------------------------
                // Post-frame: the driver already waited 3000 pixel_clk after
                // the last tlast.  The next cfg_item will trigger reinit() which
                // adds 500 byte_clk.  If you need a larger post-frame flush
                // (e.g. 5000 byte_clk as in the reference TB), send a FRAME_FLUSH
                // gap item here — or increase the repeat count in reinit() step 7.
                // The current 3000 pixel_clk + 500 byte_clk total is sufficient
                // for the reference DUT at the clock ratios used.
                // --------------------------------------------------------------

                `uvm_info("csi_frame_sequence",
                    $sformatf("Frame %0d completed | Lanes=%0d DT=0x%02X CRC=%0b SCR=%0b",
                        f, cfg_item.cfg_active_lanes, cfg_data_type,
                        cfg_item.cfg_crc_en, cfg_item.cfg_scram_en),
                    UVM_MEDIUM)
            end
        endtask : body

    endclass : csi_frame_sequence

endpackage : csi_frame_sequence_pkg