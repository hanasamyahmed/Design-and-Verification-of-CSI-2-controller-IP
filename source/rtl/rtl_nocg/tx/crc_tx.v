`timescale 1ns / 1ps

/*
===========================================================================
File Name   : crc_tx.v
Project     : MIPI CSI-2 Controller IP
Description : MIPI CSI-2 TX CRC-16 engine (CRC-CCITT, poly 0x1021 reflected)
===========================================================================
*/

module crc_tx (
    input             clk,
    input             reset_n,
    input             crc_en,
    input             i_data_valid,
    input      [7:0]  i_data_in,
    input             i_start,
    input             i_end,
    output reg        o_valid,
    output reg [7:0]  o_data
);

    reg  [15:0] crc_reg;
    reg  [1:0]  out_state;

    localparam DELAY = 9;
    reg        valid_sr [0:DELAY-1];
    reg  [7:0] data_sr  [0:DELAY-1];
    integer    d;

    reg        o_valid_pre;
    reg  [7:0] o_data_pre;

    integer     i;
    reg [15:0]  crc_pipe [0:8];
    reg [7:0]   data_pipe[0:8];

    always @(*) begin
        crc_pipe[0]  = i_start ? 16'hFFFF : crc_reg;
        data_pipe[0] = i_data_in;

        for (i = 0; i < 8; i = i + 1) begin
            if ((crc_pipe[i][0] ^ data_pipe[i][0]) == 1'b1)
                crc_pipe[i+1]  = (crc_pipe[i] >> 1) ^ 16'h8408;
            else
                crc_pipe[i+1]  = crc_pipe[i] >> 1;
            data_pipe[i+1] = data_pipe[i] >> 1;
        end
    end

    wire [15:0] crc_next = crc_pipe[8];

    // ------------------------------------------------------------------
    // Sequential CRC engine
    // ------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            crc_reg     <= 16'hFFFF;
            out_state   <= 2'd0;
            o_valid_pre <= 1'b0;
            o_data_pre  <= 8'h00;

        end else if (!crc_en) begin
            crc_reg     <= 16'hFFFF;
            out_state   <= 2'd0;
            o_valid_pre <= 1'b0;
            o_data_pre  <= 8'h00;

        end else begin
            o_valid_pre <= 1'b0;

            // PRIORITY 1: output MSB
            if (out_state == 2'd1) begin
                o_data_pre  <= crc_reg[15:8];
                o_valid_pre <= 1'b1;
                out_state   <= 2'd0;

            // PRIORITY 2: process data
            end else if (i_data_valid) begin
                crc_reg <= crc_next;

                if (i_end) begin
                    o_data_pre  <= crc_next[7:0];
                    o_valid_pre <= 1'b1;
                    out_state   <= 2'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // 9-cycle shift register delay
    // ------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (d = 0; d < DELAY; d = d + 1) begin
                valid_sr[d] <= 1'b0;
                data_sr[d]  <= 8'h00;
            end
            o_valid <= 1'b0;
            o_data  <= 8'h00;
        end else begin
            valid_sr[0] <= o_valid_pre;
            data_sr[0]  <= o_data_pre;

            for (d = 1; d < DELAY; d = d + 1) begin
                valid_sr[d] <= valid_sr[d-1];
                data_sr[d]  <= data_sr[d-1];
            end

            o_valid <= valid_sr[DELAY-1];
            o_data  <= data_sr[DELAY-1];
        end
    end

endmodule
