// =============================================================================
// Module Name : tb_csi2_rx_unpacker_adv
// File Name   : tb_csi2_rx_unpacker_adv.sv
// Author      : Hana Samy
// Date        : June 2026
// Description : Advanced self-checking verification testbench for the csi2_rx_unpacker.
//               Implements a randomized stress test across 1000 frames supporting 
//               dynamic Data Types (RAW8, 16-bit, 24-bit, RAW10). Features a 
//               scoreboard queue (golden model) checking pixel-by-pixel integrity 
//               for Data, SOF, and EOL, with automatic halting on error for rapid waveform debug.
// =============================================================================

`timescale 1ns / 1ps

module tb_csi2_rx_unpacker_adv;

    // =========================================================================
    // Parameters & Signals
    // =========================================================================
    localparam MAX_WIDTH = 24;

    logic                clk;
    logic                rst_n;
    logic [5:0]          cfg_data_type;
    logic [7:0]          rx_data;
    logic                rx_valid;
    logic                rx_packet_done;
    logic                rx_frame_start;
    
    wire [MAX_WIDTH-1:0] native_data;
    wire                 native_valid;
    wire                 native_sof;
    wire                 native_eol;

    integer              err_cnt = 0;
    integer              pass_cnt = 0;
    integer              current_frame = 0; // Tracks frame for error logging

    // Expected Data Queues (Scoreboard)
    logic [MAX_WIDTH-1:0] exp_data_q [$];
    logic                 exp_sof_q  [$];
    logic                 exp_eol_q  [$];

    // =========================================================================
    // Device Under Test (DUT)
    // =========================================================================
    csi2_rx_unpacker #(
        .MAX_PIXEL_WIDTH(MAX_WIDTH)
    ) dut (
        .i_byte_clk         (clk),
        .i_rst_n            (rst_n),
        .i_cfg_data_type    (cfg_data_type),
        .i_rx_data          (rx_data),
        .i_rx_valid         (rx_valid),
        .i_rx_packet_done   (rx_packet_done),
        .i_rx_frame_start   (rx_frame_start),
        .o_native_data      (native_data),
        .o_native_valid     (native_valid),
        .o_native_sof       (native_sof),
        .o_native_eol       (native_eol)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    // =========================================================================
    // Scoreboard Monitor (Self-Checking Logic with Enhanced Debug)
    // =========================================================================
    always @(posedge clk) begin
        if (native_valid) begin
            if (exp_data_q.size() > 0) begin
                logic [MAX_WIDTH-1:0] exp_d;
                logic                 exp_s;
                logic                 exp_e;

                exp_d = exp_data_q.pop_front();
                exp_s = exp_sof_q.pop_front();
                exp_e = exp_eol_q.pop_front();

                // Compare and Halt on Error
                if (native_data !== exp_d || native_sof !== exp_s || native_eol !== exp_e) begin
                    $display("\n=============================================");
                    $display("** FATAL ERROR ** Time: %0t", $time);
                    $display("=============================================");
                    $display(" Frame Number : %0d", current_frame);
                    $display(" Data Format  : %h", cfg_data_type);
                    $display("---------------------------------------------");
                    $display(" EXPECTED -> Data: %h | SOF: %b | EOL: %b", exp_d, exp_s, exp_e);
                    $display(" ACTUAL   -> Data: %h | SOF: %b | EOL: %b", native_data, native_sof, native_eol);
                    $display("=============================================\n");
                    err_cnt++;
                    
                    // HALT SIMULATION IMMEDIATELY
                    // This keeps the waveform right at the failure point!
                    $stop; 
                end else begin
                    pass_cnt++;
                end
            end else begin
                $display("\n** FATAL ERROR ** Time %0t | UNEXPECTED VALID PIXEL!", $time);
                $display(" DUT output valid data when the testbench expected nothing.");
                $display(" ACTUAL -> Data: %h", native_data);
                err_cnt++;
                $stop; // HALT SIMULATION
            end
        end
    end

    // =========================================================================
    // Driver Tasks
    // =========================================================================
    task send_frame_start();
        @(posedge clk);
        rx_frame_start = 1;
        rx_valid = 0;
        @(posedge clk);
        rx_frame_start = 0;
    endtask

    task send_byte_with_bubbles(input logic [7:0] data, input logic is_last);
        int delays;
        delays = $urandom_range(0, 3);
        
        for (int i = 0; i < delays; i++) begin
            @(posedge clk);
            rx_valid = 0;
            rx_packet_done = 0;
        end
        
        @(posedge clk);
        rx_valid = 1;
        rx_data = data;
        rx_packet_done = is_last;
    endtask

    task push_expected(input [MAX_WIDTH-1:0] data, input sof, input eol);
        exp_data_q.push_back(data);
        exp_sof_q.push_back(sof);
        exp_eol_q.push_back(eol);
    endtask

    // =========================================================================
    // Main Test Stimulus (1000 Randomized Iterations)
    // =========================================================================
    initial begin
        logic [5:0] formats [0:3] = '{6'h2A, 6'h1E, 6'h24, 6'h2B}; 
        logic [5:0] current_fmt;
        int         num_groups;
        logic [7:0] b0, b1, b2, b3, b4;
        logic       is_last;
        logic       is_sof;

        rst_n = 0;
        cfg_data_type = 6'h00;
        rx_data = 0; rx_valid = 0; rx_packet_done = 0; rx_frame_start = 0;
        
        #20 rst_n = 1;
        #10;

        $display("\n=============================================");
        $display(" STARTING RANDOMIZED STRESS TEST (1000 FRAMES)");
        $display("=============================================");

        for (int iter = 1; iter <= 1000; iter++) begin
            current_frame = iter; // Update tracker for error logging
            
            current_fmt = formats[$urandom_range(0, 3)];
            cfg_data_type = current_fmt;
            
            num_groups = $urandom_range(1, 10);
            
            send_frame_start();

            for (int g = 1; g <= num_groups; g++) begin
                is_last = (g == num_groups); 
                is_sof  = (g == 1);          
                
                case (current_fmt)
                    6'h2A: begin 
                        b0 = $urandom;
                        push_expected({16'h0000, b0}, is_sof, is_last);
                        send_byte_with_bubbles(b0, is_last);
                    end
                    6'h1E: begin 
                        b0 = $urandom; b1 = $urandom;
                        push_expected({8'h00, b0, b1}, is_sof, is_last);
                        send_byte_with_bubbles(b0, 1'b0);
                        send_byte_with_bubbles(b1, is_last);
                    end
                    6'h24: begin 
                        b0 = $urandom; b1 = $urandom; b2 = $urandom;
                        push_expected({b0, b1, b2}, is_sof, is_last);
                        send_byte_with_bubbles(b0, 1'b0);
                        send_byte_with_bubbles(b1, 1'b0);
                        send_byte_with_bubbles(b2, is_last);
                    end
                    6'h2B: begin 
                        b0 = $urandom; b1 = $urandom; b2 = $urandom; 
                        b3 = $urandom; b4 = $urandom;
                        
                        push_expected({14'h0000, b0, b4[1:0]}, is_sof, 1'b0);
                        push_expected({14'h0000, b1, b4[3:2]}, 1'b0,   1'b0);
                        push_expected({14'h0000, b2, b4[5:4]}, 1'b0,   1'b0);
                        push_expected({14'h0000, b3, b4[7:6]}, 1'b0,   is_last); 

                        send_byte_with_bubbles(b0, 1'b0); send_byte_with_bubbles(b1, 1'b0);
                        send_byte_with_bubbles(b2, 1'b0); send_byte_with_bubbles(b3, 1'b0);
                        send_byte_with_bubbles(b4, is_last);
                    end
                endcase
            end

            @(posedge clk);
            rx_valid = 0; rx_packet_done = 0;
            
            if (iter % 200 == 0) $display("   ... Completed %0d / 1000 iterations ...", iter);
            
            #100; 
        end

        // =====================================================================
        // Final Scoreboard Verification
        // =====================================================================
        $display("\n=============================================");
        if (err_cnt == 0 && exp_data_q.size() == 0) begin
            $display(" TEST RESULT: SUCCESS!");
            $display(" Processed 1000 random frames. All %0d pixels matched.", pass_cnt);
        end else begin
            $display(" TEST RESULT: FAILED!");
            $display(" Errors Found: %0d", err_cnt);
            if (exp_data_q.size() > 0) begin
                $display(" WARNING: %0d expected pixels were SWALLOWED by the DUT.", exp_data_q.size());
                $display(" The first swallowed pixel was -> Data: %h | SOF: %b | EOL: %b", 
                         exp_data_q[0], exp_sof_q[0], exp_eol_q[0]);
            end
        end
        $display("=============================================\n");

        $finish;
    end
endmodule