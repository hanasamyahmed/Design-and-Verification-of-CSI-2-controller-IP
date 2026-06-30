`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : csi2_ecc_tx_tb
// Description   : Directed Testbench for MIPI CSI-2 TX ECC Generator
//                 
//                 Verifies the purely combinational ECC generation logic against
//                 a software-style golden reference model. The test suite 
//                 includes edge cases (All 0s, All 1s), a walking-ones pattern 
//                 to test individual bit paths, and randomized stress testing.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : - Golden Reference Function
//                 - Self-checking verification task
//                 - Automated pass/fail reporting
//-----------------------------------------------------------------------------

module csi2_ecc_tx_tb;

    //=========================================================================
    // TESTBENCH SIGNALS
    //=========================================================================
    reg  [25:0] i_header_data;
    wire [5:0]  o_ecc;

    integer i;
    integer err_count = 0; // Tracks total failures for final report

    //=========================================================================
    // DUT INSTANTIATION
    //=========================================================================
    csi2_ecc_tx dut (
        .i_header_data (i_header_data),
        .o_ecc         (o_ecc)
    );

    //=========================================================================
    // GOLDEN REFERENCE MODEL
    //=========================================================================
    // Replicates the MIPI CSI-2 Hamming polynomial matrix behavior for 
    // verification against the RTL implementation.
    function [5:0] calculate_golden_ecc(input [25:0] d);
        reg [5:0] ecc;
        begin
            ecc[0] = d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23]^d[24];
            ecc[1] = d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23]^d[25];
            ecc[2] = d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22]^d[23];
            ecc[3] = d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[22]^d[23]^d[24]^d[25];
            ecc[4] = d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[24]^d[25];
            ecc[5] = d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23]^d[24]^d[25];

            calculate_golden_ecc = ecc;
        end
    endfunction

    //=========================================================================
    // VERIFICATION TASK
    //=========================================================================
    // Drives stimulus, waits for combinational settling, and checks output
    task check_ecc(input [25:0] test_data);
        reg [5:0] expected_ecc;
        begin
            expected_ecc  = calculate_golden_ecc(test_data);
            i_header_data = test_data;
            
            #1; // Wait 1 time unit for combinational logic propagation

            if (o_ecc !== expected_ecc) begin
                $display("[FAIL] Input: %07h | Exp ECC: %02h | Got: %02h", test_data, expected_ecc, o_ecc);
                err_count = err_count + 1;
            end else begin
                // Optional: Comment out the PASS display if the console becomes too cluttered during massive random tests
                $display("[PASS] Input: %07h | ECC: %02h", test_data, o_ecc);
            end
        end
    endtask

    //=========================================================================
    // MAIN TEST SEQUENCE
    //=========================================================================
    initial begin
        $display("=================================================");
        $display("  Starting CSI-2 TX ECC Combinational Testbench  ");
        $display("=================================================");

        //-------------------------------------------------
        // Test 1: Boundary Conditions
        //-------------------------------------------------
        $display("\n--- Running Boundary Tests ---");
        check_ecc(26'h0000000); // All Zeros
        check_ecc(26'h3FFFFFF); // All Ones

        //-------------------------------------------------
        // Test 2: Walking '1' Pattern
        //-------------------------------------------------
        // Systematically tests every individual bit path through the XOR tree
        $display("\n--- Running Walking-One Tests ---");
        for (i = 0; i < 26; i = i + 1) begin
            check_ecc(26'b1 << i);
        end

        //-------------------------------------------------
        // Test 3: Randomized Stress Test
        //-------------------------------------------------
        $display("\n--- Running Random Stress Tests ---");
        repeat (20) begin
            // Concatenate two $random calls since $random generates 32-bit signed integers
            check_ecc({$random, $random} & 26'h3FFFFFF); 
        end

        //-------------------------------------------------
        // Final Verification Report
        //-------------------------------------------------
        $display("\n=================================================");
        if (err_count == 0) begin
            $display("  [SUCCESS] ALL TESTS COMPLETED WITH 0 ERRORS!   ");
        end else begin
            $display("  [FAILED]  TEST COMPLETE WITH %0d ERRORS.       ", err_count);
        end
        $display("=================================================");

        $finish;
    end

endmodule
