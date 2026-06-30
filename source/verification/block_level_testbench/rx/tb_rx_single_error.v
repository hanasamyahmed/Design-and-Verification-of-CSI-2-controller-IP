`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : tb_rx_single
// Description   : CSI-2 Receiver ECC Single Error Correction (SEC) Testbench
//                 
//                 This directed testbench verifies the Single Error Correction 
//                 capabilities of the CSI-2 RX ECC Decoder. It uses the TX 
//                 ECC Generator as a golden reference to create a valid packet, 
//                 intentionally corrupts exactly one bit in the data payload, 
//                 and verifies that the RX module successfully detects, locates, 
//                 and corrects the error to recover the original payload.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : - Golden Model Instantiation (TX ECC)
//                 - DUT Instantiation (RX ECC)
//                 - Automated Error Injection & Self-Checking Output
//-----------------------------------------------------------------------------

module tb_rx_single;

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
    wire [25:0] corrected;      // Corrected payload from DUT
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
        $display("  Starting SEC (Single Error Correction) Test    ");
        $display("=================================================");
        rst   = 1'b1; 
        valid = 1'b0;
        data  = 26'h0000000;
        
        @(posedge clk); 
        rst = 1'b0;

        // 2. Setup Valid Payload
        data = 26'hABCDEF;
        #1; // Allow combinational TX ECC to calculate
        
        // Construct the 32-bit header
        header = {ecc_tx, data};

        // 3. Inject Single-Bit Error (SEC)
        // Flip exactly one bit in the data payload (bit 5)
        header[5] = ~header[5];

        // 4. Drive DUT
        valid = 1'b1;
        @(posedge clk);
        valid = 1'b0;
        
        // Wait for RX pipeline latency (1 cycle)
        @(posedge clk);

        // 5. Display Diagnostics
        $display("\n--- SINGLE ERROR INJECTION RESULTS ---");
        $display("RAW DATA IN        = 26'h%h", data);
        $display("TX GOLDEN ECC      = 6'b%b",  ecc_tx);
        $display("RX EXTRACTED ECC   = 6'b%b",  ecc_rx);
        $display("RX CALCULATED ECC  = 6'b%b",  ecc_calc);
        $display("ERROR SYNDROME     = 6'b%b",  syndrome);
        $display("ERROR INDEX        = 6'b%b",  error_index);
        $display("RX CORRECTED DATA  = 26'h%h", corrected);
        $display("SEC FLAG (Single)  = 1'b%b",  single_flag);
        $display("DED FLAG (Double)  = 1'b%b\n",  double_flag);

        // 6. Automated Self-Checking Assertion
        if (single_flag == 1'b1 && double_flag == 1'b0 && corrected == data) begin
            $display("[PASS] Single bit error correctly detected and fully recovered.");
        end else begin
            $display("[FAIL] SEC Flag failed to assert, or data was not correctly recovered.");
        end
        
        $display("=================================================\n");

        #20; 
        $finish;
    end

endmodule
