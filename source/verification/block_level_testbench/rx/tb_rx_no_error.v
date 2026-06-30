`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : tb_rx_no_error
// Description   : CSI-2 Receiver ECC Zero-Error (Clean Payload) Testbench
//                 
//                 This directed testbench verifies the baseline functionality 
//                 of the CSI-2 RX ECC Decoder under normal operating conditions. 
//                 It uses the TX ECC Generator as a golden reference to create 
//                 a mathematically perfect packet, transmits it to the RX 
//                 module without corruption, and verifies that the RX module 
//                 calculates a zero syndrome, flags no errors, and passes 
//                 the data through unmodified.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : - Golden Model Instantiation (TX ECC)
//                 - DUT Instantiation (RX ECC)
//                 - Automated Zero-Error Verification & Self-Checking Output
//-----------------------------------------------------------------------------

module tb_rx_no_error;

    //=========================================================================
    // TESTBENCH SIGNALS
    //=========================================================================
    // -- Clocks & Resets --
    reg         clk;
    reg         rst;
    
    // -- Data Path & Control --
    reg         valid;
    reg  [25:0] data;
    reg  [31:0] header;

    // -- Interconnects & Observability --
    wire [5:0]  ecc_tx;         // Golden ECC from TX module
    wire [25:0] corrected;      // Verified payload from DUT
    wire        single_flag;    // SEC flag from DUT
    wire        double_flag;    // DED flag from DUT
    wire        valid_out;      // Valid flag from DUT
    wire [5:0]  ecc_rx;         // Extracted ECC
    wire [5:0]  ecc_calc;       // Recalculated ECC inside DUT
    wire [5:0]  syndrome;       // Error syndrome
    wire [5:0]  error_index;    // Decoded error location

    //=========================================================================
    // CLOCK GENERATION
    //=========================================================================
    // 100 MHz Clock (10ns Period)
    initial begin
        clk = 1'b0; 
        forever #5 clk = ~clk;
    end

    //=========================================================================
    // MODULE INSTANTIATIONS
    //=========================================================================
    
    //-------------------------------------------------------------------------
    // Golden Reference Model: CSI-2 TX ECC Generator
    //-------------------------------------------------------------------------
    csi2_ecc_tx TX (
        .i_header_data (data), 
        .o_ecc         (ecc_tx)
    );

    //-------------------------------------------------------------------------
    // Device Under Test (DUT): CSI-2 RX ECC Decoder
    //-------------------------------------------------------------------------
    csi2_ecc_rx RX (
        .i_clk              (clk),
        .i_rst              (rst),
        .i_header_valid     (valid),
        .i_received_header  (header),
        
        .o_corrected_header (corrected),
        .o_single_bit_error (single_flag),
        .o_double_bit_error (double_flag),
        .o_header_valid     (valid_out),
        
        // Debug Ports
        .o_ecc_rx           (ecc_rx),
        .o_ecc_calc         (ecc_calc),
        .o_syndrome         (syndrome),
        .o_error_index      (error_index)
    );

    //=========================================================================
    // MAIN VERIFICATION SEQUENCE
    //=========================================================================
    initial begin
        // 1. Initialize Signals & Apply Reset
        $display("=================================================");
        $display("  Starting Baseline (No Error) ECC Test          ");
        $display("=================================================");
        rst   = 1'b1; 
        valid = 1'b0;
        data  = 26'h0000000;
        
        @(posedge clk); 
        rst = 1'b0;

        // 2. Setup Valid Payload
        data = 26'h123456;
        #1; // Allow combinational TX ECC to calculate
        
        // Construct the mathematically perfect 32-bit header
        header = {ecc_tx, data};

        // Note: No error injection in this testcase. 
        // The packet remains pristine.

        // 3. Drive DUT
        valid = 1'b1;
        @(posedge clk);
        valid = 1'b0;
        
        // Wait for RX pipeline latency (1 cycle)
        @(posedge clk);

        // 4. Display Diagnostics
        $display("\n--- ZERO ERROR TRANSMISSION RESULTS ---");
        $display("RAW DATA IN        = 26'h%h", data);
        $display("TX GOLDEN ECC      = 6'b%b",  ecc_tx);
        $display("RX EXTRACTED ECC   = 6'b%b",  ecc_rx);
        $display("RX CALCULATED ECC  = 6'b%b",  ecc_calc);
        $display("ERROR SYNDROME     = 6'b%b",  syndrome);
        $display("ERROR INDEX        = 6'b%b",  error_index);
        $display("RX OUTPUT DATA     = 26'h%h", corrected);
        $display("SEC FLAG (Single)  = 1'b%b",  single_flag);
        $display("DED FLAG (Double)  = 1'b%b\n",  double_flag);

        // 5. Automated Self-Checking Assertion
        if (syndrome == 6'b000000 && single_flag == 1'b0 && double_flag == 1'b0 && corrected == data) begin
            $display("[PASS] Clean packet verified successfully. No false flags asserted.");
        end else begin
            $display("[FAIL] Data mismatch or false error flags triggered on a clean packet.");
        end
        
        $display("=================================================\n");

        #20; 
        $finish;
    end

endmodule
