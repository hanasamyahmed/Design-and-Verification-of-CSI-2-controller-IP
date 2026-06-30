// =============================================================================
// File        : csi_tx_driver.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : UVM Driver for the TX input agent.
//
// REINIT SEQUENCE :
//   1. APB soft reset only (write 0x2 to reg 0 on TX and RX)
//      NO hard reset between frames. Hard reset collapses the variable-period
//        sys_clk generator and corrupts the D-PHY PLL model.
//   2. Write sideband config (cfg_active_lanes, cfg_rx_data_type, cfg_frame_lines)
//   3. repeat(10) @pclk  (let APB soft-reset propagate)
//   4. I2C TX config (slave 0x50) – NUM_PIXELS (not word count) to regs 0x00/0x01
//   5. I2C RX config (slave 0x55)
//   6. APB feature register (CRC / scrambler enable)
//   7. APB enable TX then RX
//   8. repeat(500) @byte_clk  (PHY settle)
//
// INTER-LINE GAP (matches reference TB send_frame):
//   After each line (tlast=1 accepted) the driver waits 3000 pixel_clk cycles
//   before sending the next line.  Without this gap the packetizer's
//   line-end/line-start state machine runs without any idle time, causing
//   it to misframe the next packet header → ECC double-bit errors.
//
// POST-FRAME FLUSH (matches reference TB):
//   After the last pixel of a frame is accepted the driver waits 5000 byte_clk
//   cycles to let the pipeline fully drain before the next reinit() call.
//
// =============================================================================

package csi_tx_driver_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_seq_item_pkg::*;

    class csi_tx_driver extends uvm_driver #(csi_seq_item);
        `uvm_component_utils(csi_tx_driver)

        virtual csi_tx_if tx_vif;
        virtual csi_rx_if rx_vif;

        localparam int NUM_PIXELS = 1000;
        localparam int NUM_LINES  = 100;

        // Word-count lookup: bytes per line for each CSI-2 data type
        // (kept for APB feature reg writes; I2C uses NUM_PIXELS directly)
        function automatic int get_word_count(logic [5:0] dt);
            case (dt)
                6'h2A : return 1000;   // RAW8    : 1000 pixels × 1 byte
                6'h2B : return 1250;   // RAW10   : 1000 pixels × 1.25 bytes
                6'h1E : return 2000;   // YUV422  : 1000 pixels × 2 bytes
                6'h22 : return 2000;   // RGB565  : 1000 pixels × 2 bytes
                6'h24 : return 3000;   // RGB888  : 1000 pixels × 3 bytes
                default: return 1000;
            endcase
        endfunction : get_word_count

        function new(string name = "csi_tx_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
        endfunction : build_phase

        // -----------------------------------------------------------------------
        // run_phase
        // -----------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            // Initialise all driven signals with blocking = so they take effect
            // at time 0 before any posedge occurs.
            tx_vif.tx_axis_tvalid   = 1'b0;
            tx_vif.tx_axis_tdata    = 32'd0;
            tx_vif.tx_axis_tuser    = 1'b0;
            tx_vif.tx_axis_tlast    = 1'b0;
            tx_vif.tx_apb_psel      = 1'b0;
            tx_vif.tx_apb_penable   = 1'b0;
            tx_vif.tx_apb_pwrite    = 1'b0;
            tx_vif.tx_apb_paddr     = 32'd0;
            tx_vif.tx_apb_pwdata    = 32'd0;
            rx_vif.rx_apb_psel      = 1'b0;
            rx_vif.rx_apb_penable   = 1'b0;
            rx_vif.rx_apb_pwrite    = 1'b0;
            rx_vif.rx_apb_paddr     = 32'd0;
            rx_vif.rx_apb_pwdata    = 32'd0;
            tx_vif.i2c_scl          = 1'b1;
            tx_vif.i2c_sda          = 1'b1;

            // Wait for the initial reset to be released by the tb_top initial block.
            `uvm_info(get_type_name(),
                "Waiting for hardware reset to de-assert...", UVM_LOW)
            wait(tx_vif.drv_sys_rst_n === 1'b1);
            repeat(10) @(posedge tx_vif.sys_clk);
            `uvm_info(get_type_name(),
                "Hardware is out of reset. Starting operations.", UVM_LOW)

            @(posedge tx_vif.pixel_clk);

            forever begin
                csi_seq_item req;
                seq_item_port.get_next_item(req);
                drive_item(req);
                seq_item_port.item_done();
            end
        endtask : run_phase

        // -----------------------------------------------------------------------
        // drive_item
        // -----------------------------------------------------------------------
        task drive_item(csi_seq_item item);
            // Config beat (tvalid=0) → trigger full reinit
            if (!item.tvalid) begin
                reinit(
                    item.cfg_data_type,
                    item.cfg_active_lanes,
                    item.cfg_crc_en,
                    item.cfg_scram_en,
                    $sformatf("Frame %0d reinit", item.frame_id)
                );
                @(posedge tx_vif.pixel_clk);
                return;
            end

            // Pixel beat: drive on current posedge, wait for tready
            tx_vif.tx_axis_tdata  <= item.pixel_data;
            tx_vif.tx_axis_tvalid <= 1'b1;
            tx_vif.tx_axis_tuser  <= item.tuser;
            tx_vif.tx_axis_tlast  <= item.tlast;

            do begin
                @(posedge tx_vif.pixel_clk);
            end while (tx_vif.tx_axis_tready !== 1'b1);

            // De-assert after accepted beat
            tx_vif.tx_axis_tvalid <= 1'b0;
            tx_vif.tx_axis_tuser  <= 1'b0;

            // ---------------------------------------------------------------
            // Inter-line gap: if this was end-of-line (tlast=1), wait 3000
            // pixel_clk cycles before returning so the sequence can send the
            // next line.  Matches reference TB send_frame inter-line idle.
            // Without this gap the packetizer sees back-to-back line-start
            // packets with no LP state in between → malformed headers → ECC.
            // ---------------------------------------------------------------
            if (item.tlast) begin
                tx_vif.tx_axis_tlast <= 1'b0;
                // Check if this is also end-of-frame (last line, last pixel):
                // the sequence sets tlast on every end-of-line, so we
                // distinguish end-of-frame by checking the line_id in the
                // sequence item.  End-of-frame flush is handled in the
                // post-frame gap below — we do it every tlast here because
                // the sequence only marks SOF via tuser; the driver cannot
                // easily detect EOF without peeking ahead.  A 3000-cycle gap
                // after every line (including the last) is correct — the
                // reinit() for the next frame adds 500 byte_clk on top.
                repeat(3000) @(posedge tx_vif.pixel_clk);
            end else begin
                tx_vif.tx_axis_tlast <= 1'b0;
            end

            `uvm_info("csi_tx_driver",
                $sformatf("Drove: %s", item.convert2string_stimulus()), UVM_HIGH)
        endtask : drive_item

        // -----------------------------------------------------------------------
        // APB write – TX
        // -----------------------------------------------------------------------
        task tx_apb_write(input logic [31:0] addr, input logic [31:0] data);
            @(posedge tx_vif.pclk);
            tx_vif.tx_apb_psel    <= 1'b1;
            tx_vif.tx_apb_pwrite  <= 1'b1;
            tx_vif.tx_apb_paddr   <= addr;
            tx_vif.tx_apb_pwdata  <= data;
            tx_vif.tx_apb_penable <= 1'b0;
            @(posedge tx_vif.pclk);
            tx_vif.tx_apb_penable <= 1'b1;
            @(posedge tx_vif.pclk);
            while (!tx_vif.tx_apb_pready) @(posedge tx_vif.pclk);
            tx_vif.tx_apb_psel    <= 1'b0;
            tx_vif.tx_apb_penable <= 1'b0;
            tx_vif.tx_apb_pwrite  <= 1'b0;
        endtask : tx_apb_write

        // -----------------------------------------------------------------------
        // APB write – RX
        // -----------------------------------------------------------------------
        task rx_apb_write(input logic [31:0] addr, input logic [31:0] data);
            @(posedge rx_vif.pclk);
            rx_vif.rx_apb_psel    <= 1'b1;
            rx_vif.rx_apb_pwrite  <= 1'b1;
            rx_vif.rx_apb_paddr   <= addr;
            rx_vif.rx_apb_pwdata  <= data;
            rx_vif.rx_apb_penable <= 1'b0;
            @(posedge rx_vif.pclk);
            rx_vif.rx_apb_penable <= 1'b1;
            @(posedge rx_vif.pclk);
            while (!rx_vif.rx_apb_pready) @(posedge rx_vif.pclk);
            rx_vif.rx_apb_psel    <= 1'b0;
            rx_vif.rx_apb_penable <= 1'b0;
            rx_vif.rx_apb_pwrite  <= 1'b0;
        endtask : rx_apb_write

        // -----------------------------------------------------------------------
        // I2C bit-bang (blocking = + #delays, exactly as reference TB)
        // -----------------------------------------------------------------------
        task i2c_start();
            tx_vif.i2c_sda = 0; #100;
            tx_vif.i2c_scl = 0; #100;
        endtask : i2c_start

        task i2c_stop();
            tx_vif.i2c_sda = 0; #100;
            tx_vif.i2c_scl = 1; #100;
            tx_vif.i2c_sda = 1; #100;
        endtask : i2c_stop

        task i2c_write_byte(input logic [7:0] data);
            for (int i = 7; i >= 0; i--) begin
                tx_vif.i2c_sda = data[i]; #100;
                tx_vif.i2c_scl = 1;       #200;
                tx_vif.i2c_scl = 0;       #100;
            end
            tx_vif.i2c_sda = 1; #100;
            tx_vif.i2c_scl = 1; #200;
            tx_vif.i2c_scl = 0; #100;
        endtask : i2c_write_byte

        task i2c_write_reg(
            input logic [6:0]  slave_addr,
            input logic [15:0] reg_addr,
            input logic [7:0]  data
        );
            i2c_start();
            i2c_write_byte({slave_addr, 1'b0});
            i2c_write_byte(reg_addr[15:8]);
            i2c_write_byte(reg_addr[7:0]);
            i2c_write_byte(data);
            i2c_stop();
            #1000;
        endtask : i2c_write_reg

        // -----------------------------------------------------------------------
        // reinit – matches reference TB reinit() task:
        //   • APB soft-reset ONLY (write 0x2) — no hard reset of drv_* signals
        //   • Sideband config update
        //   • I2C config using NUM_PIXELS (regs 0x0000/0x0001), not word count
        //   • PHY settle: repeat(500) @byte_clk
        //
        // POST-FRAME FLUSH:
        //   The caller (drive_item after last line tlast) already waited 3000
        //   pixel_clk cycles.  reinit() adds the APB/I2C sequence then 500
        //   byte_clk cycles.  Together this gives the pipeline time to fully
        //   drain before new config takes effect — matching reference TB which
        //   does repeat(5000) @byte_clk between send_frame and the next reinit.
        // -----------------------------------------------------------------------
        task reinit(
            input logic [5:0] dt,
            input logic [2:0] lanes,
            input logic       crc_en,
            input logic       scram_en,
            input string      label
        );
            logic [1:0]  encoded_lanes;
            int current_wc; // 1. DECLARE THE VARIABLE

        // 2. USE THE FUNCTION YOU FOUND TO GET THE EXACT BYTES
        current_wc = get_word_count(dt);

            encoded_lanes = (lanes == 3'd4) ? 2'b11 :
                            (lanes == 3'd2) ? 2'b01 : 2'b00;

            `uvm_info("csi_tx_driver",
                $sformatf("[INIT] %s | lanes=%0d DT=0x%02X CRC=%b SCR=%b",
                    label, lanes, dt, crc_en, scram_en), UVM_MEDIUM)

            // -----------------------------------------------------------------
            // STEP 1: Update sideband config (blocking = so always_ff in
            //         tb_top captures on next pclk posedge)
            // -----------------------------------------------------------------
            tx_vif.cfg_active_lanes = lanes;
            rx_vif.cfg_active_lanes = lanes;
            rx_vif.cfg_rx_data_type = dt;
            tx_vif.cfg_frame_lines  = NUM_LINES;
            tx_vif.cfg_rx_data_type = dt;
            tx_vif.cfg_crc_en       = crc_en;
            tx_vif.cfg_scram_en     = scram_en;

            repeat(5000) @(posedge tx_vif.byte_clk);
            // -----------------------------------------------------------------
        // STEP 1: HARD RESET (Required to purge Scrambler LFSR)
        // -----------------------------------------------------------------
        tx_vif.drv_sys_rst_n = 0; tx_vif.drv_preset_n = 0; tx_vif.drv_pixel_rst_n = 0; tx_vif.drv_byte_rst_n = 0;
        #200;
        tx_vif.drv_sys_rst_n = 1; tx_vif.drv_preset_n = 1; tx_vif.drv_pixel_rst_n = 1; tx_vif.drv_byte_rst_n = 1;
        repeat(20) @(posedge tx_vif.sys_clk);

            // -----------------------------------------------------------------
            // STEP 2: APB soft reset (write 0x2) – matches reference TB
            //         No hard reset: drv_* stay 1 throughout.
            // -----------------------------------------------------------------
            tx_apb_write(32'h0000_0000, 32'h0000_0002);
            rx_apb_write(32'h0000_0000, 32'h0000_0002);
            repeat(10) @(posedge tx_vif.pclk);

            // -----------------------------------------------------------------
            // STEP 3: I2C TX config – slave 0x50
            // Regs 0x0000/0x0001 = NUM_PIXELS (as in reference TB), not WC
            // -----------------------------------------------------------------
              tx_vif.i2c_write_reg(7'h50, 16'h0000,  current_wc[7:0]);
              tx_vif.i2c_write_reg(7'h50, 16'h0001, current_wc[15:8]);
              tx_vif.i2c_write_reg(7'h50, 16'h0002, {2'b00, dt});
              tx_vif.i2c_write_reg(7'h50, 16'h0003, {6'd0, encoded_lanes});
              tx_vif.i2c_write_reg(7'h50, 16'h0004, NUM_LINES[15:8]);
              tx_vif.i2c_write_reg(7'h50, 16'h0005, NUM_LINES[7:0]);

            // -----------------------------------------------------------------
            // STEP 4: I2C RX config – slave 0x55
            // -----------------------------------------------------------------
              tx_vif.i2c_write_reg(7'h55, 16'h0000, {2'b00, dt});
              tx_vif.i2c_write_reg(7'h55, 16'h0001, {6'd0, encoded_lanes});
              tx_vif.i2c_write_reg(7'h55, 16'h0002, NUM_LINES[15:8]);
              tx_vif.i2c_write_reg(7'h55, 16'h0003, NUM_LINES[7:0]);
              tx_vif.i2c_write_reg(7'h55, 16'h0004, current_wc[15:8]);
              tx_vif.i2c_write_reg(7'h55, 16'h0005, current_wc[7:0]);
            // -----------------------------------------------------------------
            // STEP 5: APB feature registers (CRC / scrambler)
            // -----------------------------------------------------------------
            tx_apb_write(32'h0000_0004, {30'd0, crc_en, scram_en});
            rx_apb_write(32'h0000_0004, {30'd0, crc_en, scram_en});
            repeat(5) @(posedge tx_vif.pclk);
            $display("DEBUG WC bytes: reg0000=0x%02X reg0001=0x%02X", NUM_PIXELS[7:0], NUM_PIXELS[15:8]);
            $display("DEBUG APB feat: 0x%08X (crc=%b scram=%b)", {30'd0,crc_en,scram_en}, crc_en, scram_en);
            // -----------------------------------------------------------------
            // STEP 6: Enable TX then RX
            // -----------------------------------------------------------------
            tx_apb_write(32'h0000_0000, 32'h0000_0001);
            rx_apb_write(32'h0000_0000, 32'h0000_0001);

            // -----------------------------------------------------------------
            // STEP 7: Wait for PHY to lock (500 byte_clk cycles).
            //         Combined with the 3000 pixel_clk inter-line gap that
            //         preceded this call, total pipeline flush > 5000 byte_clk.
            // -----------------------------------------------------------------
            `uvm_info("DRV",
                "Configuration complete, waiting for PHY to settle...", UVM_LOW)
            repeat(500) @(posedge tx_vif.byte_clk);
            `uvm_info("DRV", "Ready to send pixels!", UVM_LOW)

        endtask : reinit

    endclass : csi_tx_driver

endpackage : csi_tx_driver_pkg