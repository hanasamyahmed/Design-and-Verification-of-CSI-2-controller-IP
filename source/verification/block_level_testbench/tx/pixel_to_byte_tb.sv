// =============================================================================
// Module Name    : tb_pixel2byte
// File Name      : tb_pixel2byte.sv
// Author         : [Your Name/Engineering Team]
// Created        : June 2026
// Standard       : SystemVerilog (IEEE 1800)
// Description    : Self-checking testbench for pixel2byte_converter. 
//                  Features an automated scoreboard/predictor, dynamic driver 
//                  tasks for verifying RAW8, RGB565, RGB888, and RAW10 packed 
//                  modes, and an asynchronous monitor checking byte-by-byte 
//                  mismatches on the falling edge of the clock.
// =============================================================================

`timescale 1ns/1ps

module tb_pixel2byte;

    // ================================================================
    // 1. Signals & Constants
    // ================================================================
    parameter MAX_PIXEL_WIDTH = 24;
    localparam CLK_PERIOD     = 10;

    // DUT Control Signals
    reg                  clk = 0;
    reg                  rst_n;
    reg  [5:0]           cfg_data_type;
    reg  [15:0]          i_frame_num_lines; 
    reg  [MAX_PIXEL_WIDTH-1:0] i_data;
    reg                  i_valid;
    reg                  i_sof;
    reg                  i_eol;
    wire                 o_ready;

    // DUT Output Signals
    wire [7:0]           o_byte_data;
    wire                 o_byte_valid;
    wire                 o_frame_start;
    wire                 o_frame_end;
    wire                 o_line_start;
    wire                 o_packet_done;

    // MIPI CSI-2 Data Type Definitions
    localparam DT_RAW8   = 6'h2A;
    localparam DT_YUV422 = 6'h1E;
    localparam DT_RGB565 = 6'h22;
    localparam DT_RGB888 = 6'h24;
    localparam DT_RAW10  = 6'h2B;

    // Scoreboard / Verification Queues
    logic [7:0]          expected_q [$];
    int                  error_count = 0;
    int                  byte_count  = 0;

    // RAW10 Helper Struct for LSB packing verification
    struct {
        logic [1:0] p1, p2, p3, p4;
        int count;
    } raw10_lsb_storage;

    // ================================================================
    // 2. DUT Instantiation
    // ================================================================
    pixel2byte_converter dut (
        .i_byte_clk         (clk),
        .i_rst_n            (rst_n),
        .i_cfg_data_type    (cfg_data_type),
        .i_frame_num_lines  (i_frame_num_lines),
        .i_native_data      (i_data),
        .i_native_valid     (i_valid),
        .o_native_ready     (o_ready),
        .i_native_sof       (i_sof),
        .i_native_eol       (i_eol),

        .o_byte_data        (o_byte_data),
        .o_byte_valid       (o_byte_valid),
        .o_byte_frame_start (o_frame_start),
        .o_byte_frame_end   (o_frame_end),
        .o_byte_line_start  (o_line_start),
        .o_byte_packet_done (o_packet_done)
    );

    // Clock Generation (100MHz nominal assuming 10ns period)
    always #(CLK_PERIOD/2) clk = ~clk;

    // ================================================================
    // 3. Predictor / Scoreboard Model
    // ================================================================
    // Mirrors DUT serialization rules to queue expected output bytes
    function void predict_pixel(input [5:0] mode, input [23:0] pix);
        case (mode)
            DT_RAW8: expected_q.push_back(pix[7:0]);

            DT_RGB565: begin
                expected_q.push_back(pix[15:8]);
                expected_q.push_back(pix[7:0]);
            end

            DT_RGB888: begin
                expected_q.push_back(pix[23:16]);
                expected_q.push_back(pix[15:8]);
                expected_q.push_back(pix[7:0]);
            end

            DT_RAW10: begin
                // Push MSBs (Bits 9 down to 2)
                expected_q.push_back(pix[9:2]);

                // Accumulate LSBs across 4-pixel beats, and queue the merged byte on the 4th beat
                case (raw10_lsb_storage.count)
                    0: raw10_lsb_storage.p1 = pix[1:0];
                    1: raw10_lsb_storage.p2 = pix[1:0];
                    2: raw10_lsb_storage.p3 = pix[1:0];
                    3: begin
                        raw10_lsb_storage.p4 = pix[1:0];
                        expected_q.push_back({
                            raw10_lsb_storage.p4,
                            raw10_lsb_storage.p3,
                            raw10_lsb_storage.p2,
                            raw10_lsb_storage.p1
                        });
                        raw10_lsb_storage.count = -1; // Reset counter post packing
                    end
                endcase
                raw10_lsb_storage.count++;
            end
            default: ;
        endcase
    endfunction

    // ================================================================
    // 4. Driver Task
    // ================================================================
    task drive_frame(input [5:0] mode, input int width, input int height);
        int x, y;
        logic [23:0] rand_pix;

        $display("[TB] Driving Frame: Mode=0x%h, Size=%0dx%0d", mode, width, height);

        @(posedge clk);
        cfg_data_type     = mode;
        i_frame_num_lines = height;
        @(posedge clk);

        for (y = 0; y < height; y++) begin
            for (x = 0; x < width; x++) begin

                rand_pix = $urandom();

                // Mask off illegal bits depending on active data type
                if (mode == DT_RAW8)   rand_pix &= 24'h0000FF;
                if (mode == DT_RGB565) rand_pix &= 24'h00FFFF;
                if (mode == DT_RAW10)  rand_pix &= 24'h0003FF;

                i_valid <= 1;
                i_data  <= rand_pix;
                i_sof   <= (x == 0 && y == 0);
                i_eol   <= (x == width - 1);

                // Run golden model calculation
                predict_pixel(mode, rand_pix);

                // AXI-Stream Handshake Verification
                do begin
                    @(posedge clk);
                end while (o_ready === 1'b0);

                i_valid <= 0;
                i_sof   <= 0;
                i_eol   <= 0;

                // Add random bubbles/delays in stimulus
                if ($urandom_range(0,10) > 8)
                    @(posedge clk);
            end
            repeat(5) @(posedge clk);
        end

        repeat(20) @(posedge clk);
    endtask

    // ================================================================
    // 5. Reset Task
    // ================================================================
    task apply_reset();
        $display("\n[TB] Applying Reset...");
        rst_n             = 0;
        i_valid           = 0;
        i_data            = 0;
        i_sof             = 0;
        i_eol             = 0;
        i_frame_num_lines = 0;

        expected_q.delete();
        raw10_lsb_storage.count = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
    endtask

    // ================================================================
    // 6. Monitor / Checker
    // ================================================================
    // Evaluates data integrity on negative edge to avoid race conditions with sequential blocks
    always @(negedge clk) begin
        if (rst_n && o_byte_valid) begin
            logic [7:0] exp_byte;

            if (expected_q.size() == 0) begin
                $display("[ERROR] %t: Unexpected Output: 0x%h (Queue Empty)", $time, o_byte_data);
                error_count++;
            end
            else begin
                exp_byte = expected_q.pop_front();
                byte_count++;

                if (o_byte_data !== exp_byte) begin
                    $display("[ERROR] %t: Mismatch! Exp: 0x%h, Act: 0x%h",
                             $time, exp_byte, o_byte_data);
                    error_count++;
                end
            end
        end
    end

    // ================================================================
    // 7. Main Simulation Execution
    // ================================================================
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_pixel2byte);

        // Execute sequential protocol test vectors
        apply_reset();
        drive_frame(DT_RAW8, 8, 2);

        apply_reset();
        drive_frame(DT_RGB888, 4, 2);

        apply_reset();
        drive_frame(DT_RAW10, 8, 2);

        apply_reset();
        drive_frame(DT_RGB565, 6, 2);

        // Simulation Summary Block
        $display("==================================================");
        $display(" TEST COMPLETED");
        $display(" Total Bytes Verified : %0d", byte_count);
        $display(" Total Errors         : %0d", error_count);
        $display("==================================================");

        if (error_count == 0)
            $display(" STATUS: PASSED");
        else
            $display(" STATUS: FAILED");

        $stop;
    end

endmodule