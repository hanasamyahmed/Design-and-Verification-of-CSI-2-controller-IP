// =============================================================================
// Module Name : tb_csi2_packetizer
// File Name   : tb_csi2_packetizer.v
// Author      : Hana Samy
// Date        : June 2026
// Description : Self-checking verification testbench for the csi2_packetizer module.
//               Implements randomized packet generation (Short Packets for Frame Start/End, 
//               and Long Packets with dynamic Word Counts, Data Types, and variable CRC framing).
//               Uses a scoreboard queue (golden model) to check outgoing byte-level stream.
// =============================================================================

`timescale 1ns / 1ps

module tb_csi2_packetizer;

    // =========================================================================
    // 1. Signals & Variables
    // =========================================================================
    logic        clk;
    logic        rst_n;

    // Upstream Interface
    logic [7:0]  p2b_data;
    logic        p2b_valid;
    logic        p2b_line_start;
    logic        p2b_packet_done;
    logic        p2b_frame_start;
    logic        p2b_frame_end;

    // Configuration
    logic        cfg_crc_en;    // Toggle for CRC 
    logic [15:0] cfg_wc;
    logic [5:0]  cfg_data_type;
    logic [1:0]  cfg_vc_id;

    // External
    logic [5:0]  ecc;
    logic [7:0]  crc_data;

    // Downstream Interface
    wire [7:0]  tx_data;
    wire        tx_valid;

    // Testbench tracking
    integer      err_cnt = 0;
    integer      pass_cnt = 0;
    integer      pkt_cnt = 0;

    // Expected Data Scoreboard Queue
    logic [7:0]  exp_tx_data_q [$];

    // =========================================================================
    // 2. DUT Instantiation
    // =========================================================================
    csi2_packetizer dut (
        .i_byte_clk         (clk),
        .i_rst_n            (rst_n),
        .i_p2b_data         (p2b_data),
        .i_p2b_valid        (p2b_valid),
        .i_p2b_line_start   (p2b_line_start),
        .i_p2b_packet_done  (p2b_packet_done),
        .i_p2b_frame_start  (p2b_frame_start),
        .i_p2b_frame_end    (p2b_frame_end),
        .i_cfg_crc_en       (cfg_crc_en),   // Hooked up to DUT
        .i_cfg_wc           (cfg_wc),
        .i_cfg_data_type    (cfg_data_type),
        .i_cfg_vc_id        (cfg_vc_id),
        .i_ecc              (ecc),
        .i_crc_data         (crc_data),
        .o_tx_data          (tx_data),
        .o_tx_valid         (tx_valid)
    );

    // =========================================================================
    // 3. Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    // =========================================================================
    // 4. Scoreboard / Checker
    // =========================================================================
    always @(posedge clk) begin
        if (tx_valid) begin
            if (exp_tx_data_q.size() > 0) begin
                logic [7:0] expected_byte;
                expected_byte = exp_tx_data_q.pop_front();
                
                if (tx_data !== expected_byte) begin
                    $display("** ERROR ** Pkt %0d | Expected TX: %h | Got TX: %h", pkt_cnt, expected_byte, tx_data);
                    err_cnt++; 
                    $stop;
                end else begin
                    pass_cnt++;
                end
            end else begin
                $display("** ERROR ** Unexpected Valid TX Data: %h", tx_data);
                err_cnt++; 
                $stop;
            end
        end
    end

    // =========================================================================
    // 5. Driver Tasks
    // =========================================================================
    
    // Task: Send a Short Packet (Frame Start or Frame End)
    task send_short_packet(input logic is_frame_start, input logic [1:0] vc);
        cfg_vc_id = vc;
        ecc = $urandom;
        
        // Predict expected header based on start/end
        if (is_frame_start) begin
            p2b_frame_start = 1'b1;
            exp_tx_data_q.push_back({vc, 6'h00}); // Latched DI for Frame Start
        end else begin
            p2b_frame_end = 1'b1;
            exp_tx_data_q.push_back({vc, 6'h01}); // Latched DI for Frame End
        end
        
        // Predict rest of short packet
        exp_tx_data_q.push_back(8'h00);      // WC LSB
        exp_tx_data_q.push_back(8'h00);      // WC MSB
        exp_tx_data_q.push_back({2'b00, ecc});// ECC
        
        @(posedge clk);
        p2b_frame_start = 1'b0;
        p2b_frame_end   = 1'b0;
        
        // Increased from 10 to 25. 
        // Covers 13-cycle pipeline + 4 FSM cycles + safety margin
        repeat(25) @(posedge clk); 
    endtask

    // Task: Send a Long Packet (Line Start + Payload)
    task send_long_packet(input logic [15:0] wc, input logic [5:0] dt, input logic [1:0] vc);
        logic [7:0] p_byte;
        
        // Setup configuration
        cfg_wc        = wc;
        cfg_data_type = dt;
        cfg_vc_id     = vc;
        ecc           = $urandom;
        crc_data      = $urandom; 
        
        // Predict Long Packet Header
        exp_tx_data_q.push_back({vc, dt});
        exp_tx_data_q.push_back(wc[7:0]);
        exp_tx_data_q.push_back(wc[15:8]);
        exp_tx_data_q.push_back({2'b00, ecc});
        
        for (int i = 0; i < wc; i++) begin
            p_byte = $urandom;
            exp_tx_data_q.push_back(p_byte);
            
            p2b_valid = 1'b1;
            p2b_data  = p_byte;
            p2b_line_start  = (i == 0);          
            p2b_packet_done = (i == wc - 1);    
            
            @(posedge clk);
        end
        
        p2b_valid       = 1'b0;
        p2b_packet_done = 1'b0;
        
        if (cfg_crc_en) begin
            exp_tx_data_q.push_back(crc_data); 
            exp_tx_data_q.push_back(crc_data); 
        end
        
        // Increased from (wc + 15) to (wc + 35).
        // Covers 15-cycle ls_reg delay + 4 cycle header + payload + 2 cycle footer + safety margin
        repeat(wc + 35) @(posedge clk);
    endtask

    // =========================================================================
    // 6. Main Test Sequence
    // =========================================================================
    initial begin
        int pkt_type;
        logic [15:0] rand_wc;

        // Initialize Defaults
        p2b_data        = 0;
        p2b_valid       = 0;
        p2b_line_start  = 0;
        p2b_packet_done = 0;
        p2b_frame_start = 0;
        p2b_frame_end   = 0;
        cfg_crc_en      = 1;  // Default to CRC Enabled
        cfg_wc          = 0;
        cfg_data_type   = 0;
        cfg_vc_id       = 0;
        ecc             = 0;
        crc_data        = 0;

        // Reset Sequence
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        $display("\n=============================================");
        $display(" STARTING CSI-2 PACKETIZER RANDOMIZED TEST");
        $display("=============================================\n");

        // Run 200 random packets
        for (int i = 1; i <= 200; i++) begin
            pkt_type = $urandom_range(0, 2);
            pkt_cnt = i;
            
            // Randomize CRC Enable for each packet
            cfg_crc_en = $urandom_range(0, 1); 

            if (pkt_type == 0) begin
                // Short Packet - Frame Start
                send_short_packet(.is_frame_start(1'b1), .vc($urandom_range(0, 3)));
            end 
            else if (pkt_type == 1) begin
                // Long Packet
                rand_wc = $urandom_range(4, 64); // Payload size 4 to 64 bytes
                send_short_packet(.is_frame_start(1'b1), .vc($urandom_range(0, 3))); // Usually start with FS
                send_long_packet(.wc(rand_wc), .dt($urandom_range(16, 47)), .vc($urandom_range(0, 3)));
            end 
            else begin
                // Short Packet - Frame End
                send_short_packet(.is_frame_start(1'b0), .vc($urandom_range(0, 3)));
            end

            if (i % 50 == 0) $display("   ... Completed %0d / 200 Packets ...", i);
        end

        // Wait for everything to settle
        repeat(20) @(posedge clk);

        // =====================================================================
        // 7. Final Verification Check
        // =====================================================================
        $display("\n=============================================");
        if (err_cnt == 0 && exp_tx_data_q.size() == 0) begin
            $display(" TEST RESULT: FLAWLESS VICTORY!");
            $display(" Processed %0d packets.", pkt_cnt);
            $display(" Verified %0d output bytes with ZERO errors.", pass_cnt);
        end else begin
            $display(" TEST RESULT: FAILED!");
            $display(" Errors logged: %0d", err_cnt);
            $display(" Leftover Expected Bytes in Queue: %0d", exp_tx_data_q.size());
        end
        $display("=============================================\n");
        $finish;
    end

endmodule