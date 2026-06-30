// =============================================================================
// Module Name    : tb_axi_streaming_tx
// File Name      : tb_axi_streaming_tx.sv
// Author         : Hana Samy
// Created        : June 2026
// Standard       : SystemVerilog (IEEE 1800)
// Description    : Self-checking testbench for the axi_streaming_tx bridge. 
//                  Features a transaction-based randomized generator class, 
//                  an expected-results scoreboard (queue-based golden model) 
//                  with masking/flag evaluation logic, parallel multi-clock 
//                  driver/monitor tasks handling asynchronous CDC domains 
//                  (100MHz write, ~150MHz read), and dynamic flow control/backpressure.
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// 1. Transaction Class: Represents one Video Line
// =============================================================================
class video_transaction;
    // Randomizable Fields
    rand bit [31:0] pixel_data []; // Dynamic array of pixels
    rand int        line_length;
    rand bit [5:0]  data_type;     // MIPI Data Type
    rand int        delay_cycles;  // Idle cycles between lines

    // Constraints to generate realistic traffic
    constraint c_line_len { 
        line_length inside {[10:200]}; // Keep lines short for faster sim
    }
    
    constraint c_data_type {
        data_type inside {6'h2A, 6'h2B, 6'h2C, 6'h22, 6'h24}; // RAW8, RAW10...
    }
    
    constraint c_pixel_val {
        foreach(pixel_data[i]) pixel_data[i] dist { 
            32'h0000_0000 :/ 1, 
            32'hFFFF_FFFF :/ 1, 
            [0:$]         :/ 8 
        };
    }
    
    constraint c_delay {
        delay_cycles inside {[20:100]}; // Random wait between lines
    }

    // Helper: Resize array after randomization
    function void post_randomize();
        pixel_data = new[line_length](pixel_data);
    endfunction
endclass

// =============================================================================
// 2. Struct for Expected Results (Data + Flags)
// =============================================================================
typedef struct {
    bit [23:0] data;
    bit        sof;
    bit        eol;
} pixel_pkt_t;

// =============================================================================
// 3. Top-Level Testbench Module
// =============================================================================
module tb_axi_streaming_tx;

    // --- Parameters ---
    // Updated to match the optimized cut-through DUT defaults
    localparam FIFO_DEPTH             = 64;  
    localparam AXI_DATA_WIDTH         = 32;
    localparam MAX_PIXEL_WIDTH        = 24;
    localparam STORE_FULL_LINE        = 0;   
    localparam FIFO_START_THRESHOLD   = 16;  

    // --- Signals ---
    logic        i_pixel_clk;
    logic        i_pixel_rst_n;
    logic        i_byte_clk;
    logic        i_byte_rst_n;     // Added missing reset for read domain

    // Write Interface
    logic [31:0] i_axis_tdata;
    logic        i_axis_tvalid;
    logic        o_axis_tready;
    logic        i_axis_tuser;
    logic        i_axis_tlast;
    logic [5:0]  i_cfg_data_type;

    // Read Interface
    logic [23:0] o_native_data;
    logic        o_native_valid;
    logic        i_native_ready;
    logic        o_native_sof;
    logic        o_native_eol;
    logic        o_fifo_threshold_met;
    logic        o_fifo_stat;      // Added missing status port

    // --- Scoreboard ---
    pixel_pkt_t  expected_queue [$];
    int          error_count = 0;
    int          transaction_count = 0;

    // --- DUT Instantiation ---
    axi_streaming_tx #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .MAX_PIXEL_WIDTH(MAX_PIXEL_WIDTH),
        .STORE_FULL_LINE(STORE_FULL_LINE),
        .FIFO_START_THRESHOLD(FIFO_START_THRESHOLD)
    ) dut (
        .i_pixel_clk(i_pixel_clk),
        .i_pixel_rst_n(i_pixel_rst_n),
        .i_byte_clk(i_byte_clk),
        .i_byte_rst_n(i_byte_rst_n), // Connected read domain reset
        .i_axis_tdata(i_axis_tdata),
        .i_axis_tvalid(i_axis_tvalid),
        .o_axis_tready(o_axis_tready),
        .i_axis_tuser(i_axis_tuser),
        .i_axis_tlast(i_axis_tlast),
        .i_cfg_data_type(i_cfg_data_type),
        .o_native_data(o_native_data),
        .o_native_valid(o_native_valid),
        .i_native_ready(i_native_ready),
        .o_native_sof(o_native_sof),
        .o_native_eol(o_native_eol),
        .o_fifo_threshold_met(o_fifo_threshold_met),
        .o_fifo_stat(o_fifo_stat)    // Connected missing status port
    );

    // --- Clock Generation ---
    initial begin
        i_pixel_clk = 0;
        forever #5 i_pixel_clk = ~i_pixel_clk; // 100 MHz
    end

    initial begin
        i_byte_clk = 0;
        forever #3.33 i_byte_clk = ~i_byte_clk; // ~150 MHz (Faster Read)
    end

    // =========================================================================
    // 4. Driver Task (Stimulus)
    // =========================================================================
    task driver();
        video_transaction tr;
        tr = new();

        repeat (200) begin // Run 200 Random Video Lines
            if (!tr.randomize()) $fatal("Randomization failed!");
            
            // Setup Format
            @(posedge i_pixel_clk);
            i_cfg_data_type <= tr.data_type;
            i_axis_tvalid   <= 0;
            
            // Wait random delay between lines
            repeat(tr.delay_cycles) @(posedge i_pixel_clk);

            $display("[DRV] Sending Line %0d | Format: 0x%h | Len: %0d", 
                     transaction_count, tr.data_type, tr.line_length);

            for (int i = 0; i < tr.line_length; i++) begin
                // Wait for Ready (Flow Control)
                wait(o_axis_tready);
                
                @(posedge i_pixel_clk);
                i_axis_tvalid <= 1;
                i_axis_tdata  <= tr.pixel_data[i];
                i_axis_tuser  <= (i == 0); // SOF on first pixel
                i_axis_tlast  <= (i == tr.line_length - 1); // EOL on last pixel

                // PUSH TO SCOREBOARD (Expected Data + Expected Flags)
                push_expected_data(tr.pixel_data[i], tr.data_type, i, tr.line_length);
            end

            @(posedge i_pixel_clk);
            i_axis_tvalid <= 0;
            i_axis_tlast  <= 0;
            transaction_count++;
        end
    endtask

    // =========================================================================
    // 5. Monitor Task (Checker)
    // =========================================================================
    task monitor();
        pixel_pkt_t exp_pkt;
        
        forever begin
            @(posedge i_byte_clk);
            
            // Randomly toggle Ready to simulate backpressure (80% Ready)
            i_native_ready <= ($urandom_range(0, 10) > 2); 

            // Only check when transaction is successful (Valid & Ready)
            if (o_native_valid && i_native_ready) begin
                
                if (expected_queue.size() == 0) begin
                    $error("[MON] Unexpected Data! Queue Empty but received 0x%h", o_native_data);
                    error_count++;
                end else begin
                    // Pop the full expected packet
                    exp_pkt = expected_queue.pop_front(); 
                    
                    // --- CHECK 1: DATA ---
                    if (o_native_data !== exp_pkt.data) begin
                        $error("[MON] Data Mismatch! Exp: 0x%h | Act: 0x%h", exp_pkt.data, o_native_data);
                        error_count++;
                    end

                    // --- CHECK 2: SOF FLAG ---
                    if (o_native_sof !== exp_pkt.sof) begin
                        $error("[MON] SOF Mismatch at Data 0x%h! Exp: %b | Act: %b", o_native_data, exp_pkt.sof, o_native_sof);
                        error_count++;
                    end

                    // --- CHECK 3: EOL FLAG ---
                    if (o_native_eol !== exp_pkt.eol) begin
                        $error("[MON] EOL Mismatch at Data 0x%h! Exp: %b | Act: %b", o_native_data, exp_pkt.eol, o_native_eol);
                        error_count++;
                    end
                end
            end
        end
    endtask

    // =========================================================================
    // 6. Golden Model Logic (Helper)
    // =========================================================================
    function void push_expected_data(input bit [31:0] raw, input bit [5:0] dtype, input int idx, input int len);
        pixel_pkt_t pkt;
        bit [23:0] masked;

        // 1. Calculate Expected Data (Masking Logic)
        case (dtype)
            6'h2A: masked = {16'b0, raw[7:0]};   // RAW8
            6'h2B: masked = {14'b0, raw[9:0]};   // RAW10
            6'h2C: masked = {12'b0, raw[11:0]};  // RAW12
            6'h22: masked = {8'b0,  raw[15:0]};  // RGB565
            6'h24: masked = raw[23:0];           // RGB888
            default: masked = raw[23:0];
        endcase

        pkt.data = masked;

        // 2. Calculate Expected Flags
        pkt.sof = (idx == 0) ? 1'b1 : 1'b0;          // First pixel? Expect SOF.
        pkt.eol = (idx == len - 1) ? 1'b1 : 1'b0;    // Last pixel? Expect EOL.

        expected_queue.push_back(pkt);
    endfunction

    // =========================================================================
    // 7. Main Execution Block
    // =========================================================================
    initial begin
        // Reset
        i_pixel_rst_n  = 0;
        i_byte_rst_n   = 0;
        i_axis_tvalid  = 0;
        i_native_ready = 0;
        #100;
        i_pixel_rst_n = 1;
        i_byte_rst_n  = 1;
        
        // Run Tasks in Parallel
        fork
            driver();
            monitor();
        join_any // Wait for Driver to finish

        // Wait for FIFO to drain (give it plenty of time)
        repeat(2000) @(posedge i_byte_clk);

        // Final Check
        if (expected_queue.size() != 0) begin
            $error("[END] Test Failed: %0d items left in scoreboard!", expected_queue.size());
            error_count++;
        end

        if (error_count == 0)
            $display("\n============================================\n[PASS] All %0d Lines Verified Successfully!\n============================================", transaction_count);
        else
            $display("\n============================================\n[FAIL] Found %0d Errors.\n============================================", error_count);
        
        $finish;
    end

endmodule