
`timescale 1ns/1ps

module tb_crc_tx();

    reg         clk;
    reg         reset_n;
    reg         i_data_valid;
    reg  [7:0]  i_data_in;
    reg         i_start;
    reg         i_end;

    wire        o_valid;
    wire [7:0]  o_data;

    // DUT Instantiation
    crc_tx DUT (
        .clk(clk),
        .reset_n(reset_n),
        .i_data_valid(i_data_valid),
        .i_data_in(i_data_in),
        .i_start(i_start),
        .i_end(i_end),
        .o_valid(o_valid),
        .o_data(o_data)
    );

    // Clock generation: 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   
    end

    // ---------------------------------------------------------
    // Task: Send Payload with Synchronous Start
    // ---------------------------------------------------------
    task SEND_PAYLOAD;
        input [7:0] payload_mem[];
        integer j;
        begin
            $display("\n=== Sending Payload (%0d bytes) ===", payload_mem.size());
            
            // Loop through payload bytes
            for (j = 0; j < payload_mem.size(); j = j + 1) begin
                i_data_in    = payload_mem[j];
                i_data_valid = 1;

                // ASSERT START: Only on the first byte (j==0)
                if (j == 0)
                    i_start = 1;
                else
                    i_start = 0;

                // ASSERT END: Only on the last byte
                if (j == payload_mem.size()-1)
                    i_end = 1;
                else 
                    i_end = 0;

                @(posedge clk); // Drive inputs for one cycle
            end

            // Finish byte stream
            i_start      = 0;
            i_data_valid = 0;
            i_end        = 0;
            i_data_in    = 0;

            // Wait for CRC output (LSB and MSB)
            // Because of Look-Ahead, o_valid will be high immediately
            wait(o_valid);
            @(posedge clk);
            wait(!o_valid);

            $display("CRC output completed.\n");
        end
    endtask

    // ---------------------------------------------------------
    // Test Vectors
    // ---------------------------------------------------------
    typedef reg [7:0] BYTE;
    BYTE p1[] = '{8'hFF,8'h00,8'h00,8'h02,8'hB9,8'hDC,8'hF3,8'h72,8'hBB,8'hD4,
                  8'hB8,8'h5A,8'hC8,8'h75,8'hC2,8'h7C,8'h81,8'hF8,8'h05,8'hDF,
                  8'hFF,8'h00,8'h00,8'h01};
    BYTE p2[] = '{8'hFF,8'h00,8'h00,8'h00,8'h1E,8'hF0,8'h1E,8'hC7,8'h4F,8'h82,
                  8'h78,8'hC5,8'h82,8'hE0,8'h8C,8'h70,8'hD2,8'h3C,8'h78,8'hE9,
                  8'hFF,8'h00,8'h00,8'h01};
    BYTE p3[] = '{8'h10,8'h20,8'h30,8'h40,8'h50,8'h60,8'h70};
    BYTE p4[] = '{8'hAA,8'h55,8'hAA,8'h55,8'hAA};
    BYTE p5[] = '{8'h01,8'h02,8'h03,8'h04,8'h05,8'h06,8'h07,8'h08};

    // ---------------------------------------------------------
    // Main Block
    // ---------------------------------------------------------
    initial begin
        // Initialize signals
        reset_n      = 0;
        i_data_valid = 0;
        i_start      = 0;
        i_end        = 0;
        i_data_in    = 0;

        repeat(5) @(posedge clk);
        reset_n = 1;

        // Run tests
        SEND_PAYLOAD(p1);
        SEND_PAYLOAD(p2);
        SEND_PAYLOAD(p3);
        SEND_PAYLOAD(p4);
        SEND_PAYLOAD(p5);

        $display("=== ALL TESTS DONE ===");
        #20 $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (i_data_valid)
            $display("IN  = %02X   (valid=%b, start=%b, end=%b)", i_data_in, i_data_valid, i_start, i_end);
        if (o_valid)
            $display("OUT CRC BYTE = %02X", o_data);
    end

endmodule
