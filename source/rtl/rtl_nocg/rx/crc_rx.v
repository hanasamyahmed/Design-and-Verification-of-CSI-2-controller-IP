`timescale 1ns / 1ps

/*
=============================================================================
File Name   : crc_rx.v
Project     : MIPI CSI-2 Controller IP
Description : MIPI CSI-2 RX CRC-16 checker (CRC-CCITT, poly 0x1021 reflected)
=============================================================================
*/
module crc_rx (
    input          clk,
    input          reset_n,
    input          crc_en,
    input          i_data_valid,
    input  [7:0]   i_data_in,
    input          i_start,
    input          i_end,
    output reg     o_crc_ok,
    output reg     o_crc_done
);

    reg  [15:0] crc_reg;
    reg  [1:0]  crc_state;
    reg  [7:0]  rx_lsb;

    // --------------------------------------------------------------------------
    // Combinational: compute next CRC value
    // Use a 16-entry shift register array to avoid W415a on crc_temp
    // --------------------------------------------------------------------------
    integer     i;
    reg [15:0]  crc_pipe [0:8];   // pipeline: crc_pipe[0]=seed, crc_pipe[8]=result
    reg [7:0]   data_pipe[0:8];   // same for data_byte shifting

    always @(*) begin
        // Stage 0: seed selection
        crc_pipe[0]  = i_start ? 16'hFFFF : crc_reg;
        data_pipe[0] = i_data_in;

        // Stages 1-8: one bit per stage, no signal written twice
        for (i = 0; i < 8; i = i + 1) begin
            if ((crc_pipe[i][0] ^ data_pipe[i][0]) == 1'b1)
                crc_pipe[i+1]  = (crc_pipe[i] >> 1) ^ 16'h8408;
            else
                crc_pipe[i+1]  = crc_pipe[i] >> 1;
            data_pipe[i+1] = data_pipe[i] >> 1;
        end
    end

    wire [15:0] crc_next = crc_pipe[8];   // final result

    // --------------------------------------------------------------------------
    // Sequential: register updates only
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            crc_reg    <= 16'hFFFF;
            crc_state  <= 2'd0;
            o_crc_ok   <= 1'b0;
            o_crc_done <= 1'b0;
            rx_lsb     <= 8'h00;

        end else if (!crc_en) begin
            crc_reg    <= 16'hFFFF;
            crc_state  <= 2'd0;
            o_crc_ok   <= 1'b0;
            o_crc_done <= 1'b0;
            rx_lsb     <= 8'h00;

        end else begin
            o_crc_done <= 1'b0;
            o_crc_ok   <= 1'b0;

            // STATE 0: Payload processing
            if (i_data_valid && (crc_state == 2'd0 || i_start)) begin
                o_crc_ok <= 1'b0;
                crc_reg  <= crc_next;

                if (i_end)
                    crc_state <= 2'd1;

            // STATE 1: Receive CRC LSB
            end else if (crc_state == 2'd1 && i_data_valid) begin
                rx_lsb    <= i_data_in;
                crc_state <= 2'd2;

            // STATE 2: Receive CRC MSB and check
            end else if (crc_state == 2'd2 && i_data_valid) begin
                o_crc_ok   <= ({i_data_in, rx_lsb} == crc_reg) ? 1'b1 : 1'b0;
                o_crc_done <= 1'b1;
                crc_state  <= 2'd0;
            end
        end
    end

endmodule
