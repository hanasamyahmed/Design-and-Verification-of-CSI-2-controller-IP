
 `timescale 1ns/1ps

module tb_crc_rx;

    reg         clk;
    reg         reset_n;
    reg         i_data_valid;
    reg  [7:0]  i_data_in;
    reg         i_start;
    reg         i_end;

    wire        o_crc_ok;
    wire        o_crc_done;

    // Instantiate the DUT
    crc_rx DUT (
        .clk(clk),
        .reset_n(reset_n),
        .i_data_valid(i_data_valid),
        .i_data_in(i_data_in),
        .i_start(i_start),
        .i_end(i_end),
        .o_crc_ok(o_crc_ok),
        .o_crc_done(o_crc_done)
    );

    // Clock: 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // Task: Send Payload + CRC 
    // ---------------------------------------------------------
    task send_payload;
        input integer length;
        input [7:0] payload[];
        input [7:0] crc_lsb;
        input [7:0] crc_msb;
        integer i;
        begin
            $display("Sending Payload length %0d...", length);

            // 1. Send Payload Bytes
            for (i = 0; i < length; i = i + 1) begin
                i_data_in    = payload[i];
                i_data_valid = 1;

                // SYNC START: Assert start only on first byte in same cycle
                if (i == 0) i_start = 1;
                else        i_start = 0;

                // END FLAG: Assert end only on last byte
                if (i == length-1) i_end = 1;
                else               i_end = 0;

                @(posedge clk);
            end

            // Clear Control Signals
            i_start = 0;
            i_end   = 0;

            // 2. Immediately Send CRC LSB (Zero Latency)
            i_data_in    = crc_lsb;
            i_data_valid = 1;
            @(posedge clk);

            // 3. Send CRC MSB
            i_data_in    = crc_msb;
            i_data_valid = 1;
            @(posedge clk);

            // 4. Finish
            i_data_valid = 0;
            i_data_in    = 0;
            @(posedge clk);
        end
    endtask

    // Payloads
    reg [7:0] p1[0:23];
    reg [7:0] p2[0:23];

    initial begin
        // Payload 1 (Correct CRC: F0 01)
        p1 = '{8'hFF,8'h00,8'h00,8'h02,8'hB9,8'hDC,8'hF3,8'h72,8'hBB,8'hD4,
               8'hB8,8'h5A,8'hC8,8'h75,8'hC2,8'h7C,8'h81,8'hF8,8'h05,8'hDF,
               8'hFF,8'h00,8'h00,8'h01};
               
        // Payload 2 (Correct CRC: 69 E5)
        p2 = '{8'hFF,8'h00,8'h00,8'h00,8'h1E,8'hF0,8'h1E,8'hC7,8'h4F,8'h82,
               8'h78,8'hC5,8'h82,8'hE0,8'h8C,8'h70,8'hD2,8'h3C,8'h78,8'hE9,
               8'hFF,8'h00,8'h00,8'h01};

        // Initialize
        reset_n = 0;
        i_data_valid = 0;
        i_data_in = 0;
        i_start = 0;
        i_end = 0;

        repeat (5) @(posedge clk);
        reset_n = 1;

        // --- Run Tests ---
        
        // 1. Send Correct Packet
        send_payload(24, p1, 8'hF0, 8'h01);
        
        repeat(2) @(posedge clk);

        // 2. Send Correct Packet 2
        send_payload(24, p2, 8'h69, 8'hE5);
        
        // 3. Send Corrupt Packet (Deliberate Error Test)
        // Sending p1 but with wrong CRC (AA BB) to verify o_crc_ok goes low
        $display("Sending Corrupt Packet (Expect Fail)...");
        send_payload(24, p1, 8'hAA, 8'hBB);

        $display("=== Test complete ===");
        #50 $finish;
    end

    // Monitor Results
    always @(posedge clk) begin
        if (o_crc_done) begin
            if (o_crc_ok) 
                $display("[%0t] PASS: CRC Match Detected", $time);
            else 
                $display("[%0t] FAIL: CRC Mismatch Detected (Expected)", $time);
        end
    end

endmodule
