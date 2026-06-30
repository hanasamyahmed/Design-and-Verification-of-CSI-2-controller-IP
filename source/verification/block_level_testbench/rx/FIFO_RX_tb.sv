// =============================================================================
// Module Name : tb_async_fifo
// File Name   : tb_async_fifo.sv
// Author      : Hana Samy 
// Date        : June 2026
// Description : Self-checking verification testbench for the asynchronous FIFO.
//               Implements OOP transaction constraints for randomized delays,
//               dual-clock domain generation (Write: 100MHz, Read: ~75MHz), 
//               a scoreboard queue for functional correctness, and parallel 
//               fork/join threads for concurrent producer/consumer verification.
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// 1. Transaction Object
// =============================================================================
// Class encapsulating random data and control delays for stimulus generation
class fifo_transaction #(parameter WIDTH=26);
    rand bit [WIDTH-1:0] data;
    rand int write_delay; 
    rand int read_delay; 

    constraint c_delays {
        write_delay inside {[0:5]}; 
        read_delay  inside {[0:5]};
    }
endclass

// =============================================================================
// 2. Top-Level Testbench
// =============================================================================
module tb_async_fifo;

    // --- Configuration ---
    localparam WIDTH = 26;      
    localparam DEPTH = 64;      

    // --- Signals ---
    logic             wclk, wrst_n, winc, wfull;
    logic [WIDTH-1:0] wdata;
    
    logic             rclk, rrst_n, rinc, rempty;
    logic [WIDTH-1:0] rdata;
    logic [$clog2(DEPTH):0] rd_count;

    // --- Scoreboard ---
    // Queue acting as a golden model to store expected data transactions
    bit [WIDTH-1:0] expected_queue [$];
    int error_count = 0;
    int write_count = 0;
    int read_count  = 0;

    // --- Clock Generation ---
    // Write clock domain: 100 MHz (period = 10ns)
    initial begin
        wclk = 0;
        forever #5 wclk = ~wclk; 
    end

    // Read clock domain: ~75 MHz (period = 13.33ns, toggle every 6.66ns) - asynchronous to wclk
    initial begin
        rclk = 0;
        forever #6.66 rclk = ~rclk; 
    end

    // --- DUT Instantiation ---
    async_fifo_behavioral #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty),
        .rd_count(rd_count)
    );

    // =========================================================================
    // 3. Write Task (Producer)
    // =========================================================================
    task producer(int num_transactions);
        fifo_transaction #(WIDTH) tr; 
        tr = new(); 
        
        $display("[%0t] [WRITE] Starting Producer for %0d items...", $time, num_transactions);

        repeat (num_transactions) begin
            // Randomize delays and payload data
            if (!tr.randomize()) $fatal("Randomization Failed");
            repeat (tr.write_delay) @(posedge wclk);

            // Align to active region AFTER Non-Blocking Assignment (NBA) updates
            #1; 
            while (wfull === 1'b1) begin
                @(posedge wclk);
                #1; // Re-evaluate full flag cleanly after the next clock edge
            end

            // Push transaction to the DUT and scoreboard
            winc  <= 1;
            wdata <= tr.data;
            expected_queue.push_back(tr.data); 
            
            @(posedge wclk);
            winc  <= 0;
            wdata <= '0; 
            write_count++;
        end
        $display("[%0t] [WRITE] Finished. Wrote %0d items.", $time, write_count);
    endtask

    // =========================================================================
    // 4. Read Task (Consumer)
    // =========================================================================
    task consumer(int num_transactions);
        fifo_transaction #(WIDTH) tr; 
        bit [WIDTH-1:0] expected_data;
        bit [WIDTH-1:0] actual_data;
        tr = new();

        $display("[%0t] [READ] Starting Consumer for %0d items...", $time, num_transactions);

        repeat (num_transactions) begin
            if (!tr.randomize()) $fatal("Randomization Failed");
            repeat (tr.read_delay) @(posedge rclk);

            // Ensure 'rempty' is evaluated cleanly after clock edge
            #1; 
            while (rempty === 1'b1) begin
                @(posedge rclk);
                #1;
            end

            // Capture Data (First-Word Fall-Through (FWFT) makes data available before rinc)
            actual_data = rdata; 

            // Consume Data (Pulse Read Increment)
            rinc <= 1;
            @(posedge rclk);
            rinc <= 0;

            // Functional verification against golden scoreboard model
            if (expected_queue.size() == 0) begin
                $error("[%0t] [READ] Underflow! FIFO gave data 0x%h, but Scoreboard is empty.", $time, actual_data);
                error_count++;
            end else begin
                expected_data = expected_queue.pop_front();
                if (actual_data !== expected_data) begin
                    $error("[%0t] [READ] Mismatch! Exp: 0x%h | Act: 0x%h", $time, expected_data, actual_data);
                    error_count++;
                end
            end
            read_count++;
        end
        $display("[%0t] [READ] Finished. Read %0d items.", $time, read_count);
    endtask

    // =========================================================================
    // 5. Main Execution
    // =========================================================================
    initial begin
        // Initialize control signals
        winc  = 0; wdata = 0; wrst_n = 0;
        rinc  = 0; rrst_n = 0;
        
        // Deassert resets after 50ns
        #50 wrst_n = 1; rrst_n = 1; #50;

        // Launch producer and consumer concurrently
        fork
            producer(1000);
            consumer(1000);
        join

        // Drain / Post-test emptiness check
        repeat(20) @(posedge rclk);
        if (rempty === 0) 
            $error("[%0t] [END] FIFO not empty after test!", $time);

        // Final test summary report
        if (error_count == 0)
            $display("\n[PASS] Test Passed! %0d Transactions Verified.", read_count);
        else
            $display("\n[FAIL] Test Failed with %0d Errors.", error_count);

        $finish;
    end

endmodule