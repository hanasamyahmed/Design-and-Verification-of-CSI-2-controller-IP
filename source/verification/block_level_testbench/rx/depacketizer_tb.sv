// =============================================================================
// Module Name : tb_rx_depacketizer
// File Name   : tb_rx_depacketizer.sv
// Author      : Hana Samy
// Date        : June 2026
// Description : Self-checking testbench for the rx_depacketizer module. 
//               Implements automated regression testing covering Short Packets, 
//               Long Packets (RAW10) with/without CRC, Frame Start markers, 
//               ECC word count overrides, and ECC Double Error abort scenarios.
// =============================================================================

`timescale 1ns / 1ps

module tb_rx_depacketizer();

    // -------------------------------------------------------------------------
    // Clock and Reset Generation
    // -------------------------------------------------------------------------
    reg i_clk;
    reg i_rst_n;
    
    // 50MHz Clock generation (period = 20ns, toggle every 10ns)
    initial i_clk = 1'b0;
    always #10 i_clk = ~i_clk; 

    // -------------------------------------------------------------------------
    // DUT Interface Signals
    // -------------------------------------------------------------------------
    // Configuration & Input
    reg         i_cfg_crc_en;
    reg  [7:0]  i_rx_data;
    reg         i_rx_valid;
    
    // Payload Stream Outputs
    wire [7:0]  o_pay_data;
    wire        o_pay_valid;
    wire        o_pay_last;
    wire        o_pay_user;
    
    // Header Processing Outputs
    wire [31:0] o_ecc_hdr_data;
    wire        o_hdr_captured;
    
    // ECC Feedback Inputs
    reg  [25:0] i_ecc_corrected_header;
    reg         i_ecc_header_valid;
    reg         i_ecc_double_err;
    
    // CRC Interface Outputs
    wire [7:0]  o_crc_data;
    wire        o_crc_valid;
    wire        o_crc_start;
    wire        o_crc_end;

    // -------------------------------------------------------------------------
    // Scoreboard / Tracker Pools
    // -------------------------------------------------------------------------
    integer error_count = 0;
    integer checked_pay_valids;
    integer checked_crc_valids;
    integer hdr_captured_count;
    integer pay_user_at_count;
    reg     last_seen_pay_last;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // -------------------------------------------------------------------------
    rx_depacketizer uut (
        .i_clk                   (i_clk), 
        .i_rst_n                 (i_rst_n), 
        .i_cfg_crc_en            (i_cfg_crc_en),
        .i_rx_data               (i_rx_data), 
        .i_rx_valid              (i_rx_valid), 
        .o_pay_data              (o_pay_data),
        .o_pay_valid             (o_pay_valid), 
        .o_pay_last              (o_pay_last), 
        .o_pay_user              (o_pay_user),
        .o_ecc_hdr_data          (o_ecc_hdr_data), 
        .o_hdr_captured          (o_hdr_captured),
        .i_ecc_corrected_header  (i_ecc_corrected_header), 
        .i_ecc_header_valid      (i_ecc_header_valid),
        .i_ecc_double_err        (i_ecc_double_err), 
        .o_crc_data              (o_crc_data),
        .o_crc_valid             (o_crc_valid), 
        .o_crc_start             (o_crc_start), 
        .o_crc_end               (o_crc_end)
    );

    // -------------------------------------------------------------------------
    // Mock ECC Block Configuration
    // -------------------------------------------------------------------------
    reg          mock_ecc_inject_err;
    reg          mock_ecc_inject_correction;
    reg  [15:0]  mock_corrected_wc;

    // Behavioral block to simulate ECC pipeline responses based on header capture
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            i_ecc_header_valid     <= 1'b0;
            i_ecc_double_err       <= 1'b0;
            i_ecc_corrected_header <= 26'd0;
        end else begin
            i_ecc_header_valid <= 1'b0;
            i_ecc_double_err   <= 1'b0;
            
            if (o_hdr_captured) begin
                if (mock_ecc_inject_err) begin
                    i_ecc_double_err <= 1'b1;
                end else if (mock_ecc_inject_correction) begin
                    i_ecc_header_valid     <= 1'b1;
                    // Inject corrected word count into header pipeline bits
                    i_ecc_corrected_header <= {2'b00, mock_corrected_wc, o_ecc_hdr_data[7:0]};
                end else begin
                    i_ecc_header_valid     <= 1'b1;
                    i_ecc_corrected_header <= o_ecc_hdr_data[25:0];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Performance Scoreboard Monitor
    // -------------------------------------------------------------------------
    // Samples outputs on every clock cycle to accumulate statistics for assertions
    always @(posedge i_clk) begin
        if (o_hdr_captured) 
            hdr_captured_count = hdr_captured_count + 1;
            
        if (o_pay_valid) begin
            checked_pay_valids = checked_pay_valids + 1;
            
            if (o_pay_user) 
                pay_user_at_count = checked_pay_valids;
                
            if (o_pay_last) 
                last_seen_pay_last = 1'b1;
        end
        
        if (o_crc_valid) 
            checked_crc_valids = checked_crc_valids + 1;
    end

    // -------------------------------------------------------------------------
    // Testbench Subroutines & Tasks
    // -------------------------------------------------------------------------
    
    // Task: reset_system
    // Asserts asynchronous reset and clears tracking variables
    task reset_system;
        begin
            i_clk = 0; i_rst_n = 0; i_cfg_crc_en = 0; i_rx_data = 8'd0; i_rx_valid = 0;
            mock_ecc_inject_err = 0; mock_ecc_inject_correction = 0; mock_corrected_wc = 16'd0;
            clear_trackers();
            repeat(5) @(posedge i_clk);
            i_rst_n = 1;
            repeat(2) @(posedge i_clk);
        end
    endtask

    // Task: clear_trackers
    // Resets scoreboard counters to baseline
    task clear_trackers;
        begin
            checked_pay_valids   = 0;
            checked_crc_valids   = 0;
            hdr_captured_count   = 0;
            pay_user_at_count    = 0;
            last_seen_pay_last   = 0;
        end
    endtask

    // Task: assert_eq
    // Evaluates simulation coverage vs expected scoreboards
    task assert_eq(input [32*8:1] signal_name, input integer actual, input integer expected);
        begin
            if (actual !== expected) begin
                $display("   [FAIL] %0s check failed! Expected: %0d, Got: %0d", signal_name, expected, actual);
                error_count = error_count + 1;
            end else begin
                $display("   [PASS] %0s passed evaluation (%0d)", signal_name, actual);
            end
        end
    endtask

    // Task: send_byte
    // Drives a single byte over the byte-streaming interface with optional idle insertion
    task send_byte(input [7:0] data, input integer stall_cycles);
        begin
            if (stall_cycles > 0) begin
                i_rx_valid = 1'b0;
                repeat(stall_cycles) @(posedge i_clk);
            end
            i_rx_valid = 1'b1; i_rx_data = data;
            @(posedge i_clk);
            i_rx_valid = 1'b0; 
        end
    endtask

    // Task: send_packet
    // Sequences complete packets including headers, payload, and CRC footers
    task send_packet(input [7:0] di, input [15:0] wc, input has_crc, input integer phy_gaps);
        integer i;
        begin
            // 4-Byte Header Framing
            send_byte(di, 0);
            send_byte(wc[7:0], 0);
            send_byte(wc[15:8], 0);
            send_byte(8'hAA, 0); 

            // Payload and Footer Generation for Long Packet Types
            if (di[5:4] != 2'b00) begin
                for (i = 0; i < wc; i = i + 1) begin
                    send_byte(i[7:0], phy_gaps);
                end
                if (has_crc) begin
                    send_byte(8'hC1, phy_gaps);
                    send_byte(8'hC2, phy_gaps);
                end
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Stimulus Initial Block
    // -------------------------------------------------------------------------
    initial begin
        $display("=================================================================");
        $display("STARTING AUTOMATED SELF-CHECKING REGRESSION SUITE");
        $display("=================================================================");

        // [TEST 1] Short Packet Handling (Frame Start 0x00)
        reset_system();
        $display("\n[RUNNING TEST 1] Short Packet Handling (Frame Start 0x00)");
        i_cfg_crc_en = 1'b1;
        send_packet(8'h00, 16'h0005, 0, 0); 
        repeat(5) @(posedge i_clk);
        assert_eq("Header Capture Pulse Count", hdr_captured_count, 0);
        assert_eq("Payload Valid Count",        checked_pay_valids, 0);

        // [TEST 2] Long Packet (RAW10) - CRC Disabled
        reset_system();
        $display("\n[RUNNING TEST 2] Long Packet (RAW10) - CRC Disabled");
        i_cfg_crc_en = 1'b0;
        send_packet(8'h2B, 16'd5, 0, 0); 
        repeat(5) @(posedge i_clk);
        assert_eq("Header Capture Pulse Count", hdr_captured_count, 1);
        assert_eq("Payload Valid Count",        checked_pay_valids, 5);
        assert_eq("Payload Last Assert Flag",   last_seen_pay_last, 1);
        assert_eq("CRC Engine Valid Count",     checked_crc_valids, 5);

        // [TEST 3] Long Packet (RAW10) - CRC Enabled
        reset_system();
        $display("\n[RUNNING TEST 3] Long Packet (RAW10) - CRC Enabled");
        i_cfg_crc_en = 1'b1;
        send_packet(8'h2B, 16'd4, 1, 0); 
        repeat(5) @(posedge i_clk);
        assert_eq("Payload Valid Count",        checked_pay_valids, 4);
        assert_eq("Payload Last Assert Flag",   last_seen_pay_last, 1);
        assert_eq("CRC Engine Valid Count",     checked_crc_valids, 6);

        // [TEST 4] Frame Start Sequence (o_pay_user Assertion Check)
        reset_system();
        $display("\n[RUNNING TEST 4] Frame Start Sequence (o_pay_user Assertion Check)");
        i_cfg_crc_en = 1'b1;
        send_packet(8'h00, 16'h0001, 0, 0); 
        send_packet(8'h2B, 16'd3, 1, 0);    
        repeat(5) @(posedge i_clk);
        assert_eq("Payload Valid Count",        checked_pay_valids, 3);
        assert_eq("o_pay_user Trigger Index",   pay_user_at_count,  1);

        // [TEST 5] ECC Corrected Word Count Override
        reset_system();
        $display("\n[RUNNING TEST 5] ECC Corrected Word Count Override");
        mock_ecc_inject_correction = 1'b1;
        mock_corrected_wc          = 16'd3; 
        i_cfg_crc_en               = 1'b1;
        send_packet(8'h2B, 16'd12, 1, 0); 
        mock_ecc_inject_correction = 1'b0; 
        repeat(5) @(posedge i_clk);
        assert_eq("Payload Valid Count (Overridden)", checked_pay_valids, 3); 
        assert_eq("Payload Last Assert Flag",         last_seen_pay_last, 1);
        assert_eq("CRC Engine Valid Count",           checked_crc_valids, 5);

        // [TEST 6] ECC Double Error Abort & FSM Flush Recovery
        reset_system();
        $display("\n[RUNNING TEST 6] ECC Double Error Abort & FSM Flush Recovery");
        i_cfg_crc_en        = 1'b1;
        mock_ecc_inject_err = 1'b1;
        send_packet(8'h2B, 16'd8, 1, 0); 
        mock_ecc_inject_err = 1'b0;
        repeat(5) @(posedge i_clk);
        
        send_packet(8'h2B, 16'd2, 1, 0); 
        repeat(5) @(posedge i_clk);
        assert_eq("Header Capture Pulse Count",      hdr_captured_count, 2);
        assert_eq("Total Accumulated Payload Valids", checked_pay_valids, 4);

        // [TEST 7] Footer Valid Stall (Un-Stick Fix Assert)
        reset_system(); 
        $display("\n[RUNNING TEST 7] Footer Valid Stall (Un-Stick Fix Assert)");
        i_cfg_crc_en = 1'b1;
        send_packet(8'h2B, 16'd3, 1, 2); 
        repeat(10) @(posedge i_clk);
        assert_eq("Payload Valid Count",    checked_pay_valids, 3);
        assert_eq("CRC Engine Valid Count", checked_crc_valids, 9); 

        // ---------------------------------------------------------------------
        // Regression Report
        // ---------------------------------------------------------------------
        $display("\n=================================================================");
        if (error_count == 0) begin
            $display("  REGRESSION STATUS: SUCCESSFUL! ALL CHECKS PASSED.");
        end else begin
            $display("  REGRESSION STATUS: FAILED WITH %0d ERRORS.", error_count);
        end
        $display("=================================================================");
        $finish;
    end
endmodule