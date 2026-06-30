// =============================================================================
// Module Name : tb_axi_stream_bridge
// File Name   : tb_axi_stream_bridge.sv
// Author      : Hana Samy 
// Date        : June 2026
// Description : Self-checking verification testbench for the axi_stream_bridge module.
//               Implements OOP transaction constraints for randomized gaps and 
//               backpressure, a scoreboard struct queue for functional correctness,
//               and parallel fork/join verification threads (Driver/Monitor).
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// 1. Transaction Object
// =============================================================================
// Class encapsulating random pixel data, framing sidebands, and delay constraints
class bridge_transaction #(parameter PIX_WIDTH=24);
    rand bit [PIX_WIDTH-1:0] data;
    rand bit                 last; // End of Line (EOL)
    rand bit                 user; // Start of Frame (SOF)
    rand int                 input_delay; // bubbles/gaps before sending
    rand int                 ready_delay; // backpressure delay from downstream slave

    constraint c_delays {
        input_delay inside {[0:3]}; 
        ready_delay inside {[0:3]};
        input_delay dist {0:=80, [1:3]:20}; 
        ready_delay dist {0:=80, [1:3]:20};
    }
endclass

// =============================================================================
// 2. Testbench Module
// =============================================================================
module tb_axi_stream_bridge;

    // --- Configuration ---
    localparam P_PIX_WIDTH = 24; 
    localparam P_AXI_WIDTH = 32;

    // --- Typedef for Scoreboard ---
    // Packs expected stream payload for golden model validation
    typedef struct packed {
        bit [P_PIX_WIDTH-1:0] data;
        bit last;
        bit user;
    } pixel_s;

    // --- System & Interface Signals ---
    logic                     aclk;
    logic                     aresetn;
    logic [P_PIX_WIDTH-1:0]   i_pix_data;
    logic                     i_pix_last;
    logic                     i_pix_user;
    logic                     i_pix_valid;
    logic                     o_pix_ready;
    logic [P_AXI_WIDTH-1:0]       m_axis_tdata;
    logic [(P_AXI_WIDTH/8)-1:0]   m_axis_tkeep;
    logic                         m_axis_tlast;
    logic                         m_axis_tuser;
    logic                         m_axis_tvalid;
    logic                         m_axis_tready;

    // --- Scoreboard Queue ---
    // Holds golden transactions for deterministic pass/fail evaluation
    pixel_s expected_q [$];
    int error_count = 0;

    // --- DUT Instantiation ---
    axi_stream_bridge #(
        .P_PIX_WIDTH(P_PIX_WIDTH),
        .P_AXI_WIDTH(P_AXI_WIDTH)
    ) dut (
        .i_aclk(aclk),
        .i_aresetn(aresetn),
        .i_pix_data(i_pix_data),
        .i_pix_last(i_pix_last),
        .i_pix_user(i_pix_user),
        .i_pix_valid(i_pix_valid),
        .o_pix_ready(o_pix_ready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready)
    );

    // --- Clock Generation (100 MHz) ---
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk; 
    end

    // =========================================================================
    // 3. Driver Task (Producer)
    // =========================================================================
    // Sequences randomized transactions into the DUT input port
    task automatic drive_input(int num_tx);
        bridge_transaction #(P_PIX_WIDTH) tr; 
        pixel_s tmp_pix;

        tr = new();
        $display("[DRIVER] Starting... Sending %0d pixels.", num_tx);

        repeat(num_tx) begin
            if (!tr.randomize()) $error("Randomization failed");

            // 1. Insert variable bubbles (idle cycles)
            i_pix_valid <= 0;
            repeat(tr.input_delay) @(posedge aclk);

            // 2. Drive payload and sidebands
            i_pix_valid <= 1;
            i_pix_data  <= tr.data;
            i_pix_last  <= tr.last;
            i_pix_user  <= tr.user;

            // 3. Push active transaction to scoreboard golden queue
            tmp_pix.data = tr.data;
            tmp_pix.last = tr.last;
            tmp_pix.user = tr.user;
            expected_q.push_back(tmp_pix);

            // 4. Wait for upstream acceptance (backpressure handshaking)
            do begin
                @(posedge aclk);
            end while (o_pix_ready == 0); 

            i_pix_valid <= 0;
        end
        
        i_pix_valid <= 0;
        $display("[DRIVER] Finished.");
    endtask

    // =========================================================================
    // 4. Receiver Task (Monitor / Checker)
    // =========================================================================
    // Samples AXI4-Stream master interface and verifies zero-padding correctness
    task automatic monitor_output(int num_tx);
        bridge_transaction #(P_PIX_WIDTH) tr; 
        bit [P_AXI_WIDTH-1:0] expected_padded_data;
        bit [P_PIX_WIDTH-1:0] exp_raw;
        bit                   exp_last, exp_user;
        pixel_s               exp_struct;
        int                   received_cnt;

        tr = new();
        received_cnt = 0;
        
        $display("[MONITOR] Starting...");

        while (received_cnt < num_tx) begin
            if (!tr.randomize()) $error("Randomization failed");

            // 1. Apply downstream random backpressure
            m_axis_tready <= 0;
            repeat(tr.ready_delay) @(posedge aclk);
            m_axis_tready <= 1;

            // 2. Validate stream upon active handshake
            @(posedge aclk);
            if (m_axis_tvalid && m_axis_tready) begin
                if (expected_q.size() == 0) begin
                    $error("[MONITOR] Error: Unexpected output data! Queue empty.");
                    error_count++;
                end else begin
                    exp_struct = expected_q.pop_front();
                    
                    exp_raw  = exp_struct.data;
                    exp_last = exp_struct.last;
                    exp_user = exp_struct.user;

                    // Compute expected zero padding for 24-bit to 32-bit word mapping
                    expected_padded_data = { {(P_AXI_WIDTH-P_PIX_WIDTH){1'b0}}, exp_raw };

                    // Data integrity assertions
                    if (m_axis_tdata !== expected_padded_data) begin
                        $error("[MONITOR] Data Mismatch! Exp: %h | Act: %h", expected_padded_data, m_axis_tdata);
                        error_count++;
                    end
                    if (m_axis_tlast !== exp_last) begin
                        $error("[MONITOR] TLAST Mismatch! Exp: %b | Act: %b", exp_last, m_axis_tlast);
                        error_count++;
                    end
                    if (m_axis_tuser !== exp_user) begin
                        $error("[MONITOR] TUSER Mismatch! Exp: %b | Act: %b", exp_user, m_axis_tuser);
                        error_count++;
                    end
                    if (m_axis_tkeep !== {(P_AXI_WIDTH/8){1'b1}}) begin
                        $error("[MONITOR] TKEEP Mismatch! Exp: All 1s | Act: %b", m_axis_tkeep);
                        error_count++;
                    end
                end
                received_cnt++;
            end
        end
        $display("[MONITOR] Finished. Received %0d pixels.", received_cnt);
    endtask

    // =========================================================================
    // 5. Main Execution Block
    // =========================================================================
    initial begin
        // Initialize ports and hard resets
        i_pix_valid   = 0;
        i_pix_data    = 0;
        m_axis_tready = 0;
        aresetn       = 0;

        #20 aresetn = 1;
        #20;

        // Launch Driver & Monitor in parallel threads
        fork
            drive_input(1000);   
            monitor_output(1000);
        join

        // Report global evaluation
        if (error_count == 0)
            $display("\n[PASS] Test Passed! 1000 Transactions Verified.");
        else
            $display("\n[FAIL] Test Failed with %0d Errors.", error_count);

        $finish;
    end

endmodule