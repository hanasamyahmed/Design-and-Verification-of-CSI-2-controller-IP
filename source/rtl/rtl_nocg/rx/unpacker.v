// =============================================================================
// Module Name : csi2_rx_unpacker
// File Name   : csi2_rx_unpacker.v
// Author      : Hana Samy
// Date        : June 2026
// Description : Unpacks MIPI CSI-2 byte streams into native pixel formats 
//               (RAW8, 16-bit, 24-bit, RAW10) based on data type configuration. 
//               Accumulates bytes, handles reverse gearboxing for RAW10 bursts, 
//               and aligns sideband flags (SOF/EOL) to native pixel boundaries.
// =============================================================================

`timescale 1ns / 1ps

module csi2_rx_unpacker #(
    parameter MAX_PIXEL_WIDTH = 24
)(
    // Clocks and Resets
    input  wire                         i_byte_clk,
    input  wire                         i_rst_n,

    // Configuration
    input  wire [5:0]                   i_cfg_data_type,

    // Byte Input Interface (From Depacketizer)
    input  wire [7:0]                   i_rx_data,
    input  wire                         i_rx_valid,
    input  wire                         i_rx_packet_done,
    input  wire                         i_rx_frame_start,

    // Native Output Interface (To Async FIFO)
    output wire [MAX_PIXEL_WIDTH-1:0]   o_native_data,
    output wire                         o_native_valid,
    output wire                         o_native_sof,
    output wire                         o_native_eol
);

    // =========================================================================
    // Internal Signals & Types
    // =========================================================================
    
    // Data Type decoding
    wire is_raw8  = (i_cfg_data_type == 6'h2A);
    wire is_2byte = (i_cfg_data_type == 6'h1E) || (i_cfg_data_type == 6'h22);
    wire is_3byte = (i_cfg_data_type == 6'h24);
    wire is_raw10 = (i_cfg_data_type == 6'h2B);

    // Byte Accumulator
    reg [2:0] byte_cnt;
    reg [7:0] r_byte0, r_byte1, r_byte2, r_byte3;
    
    // SOF Tracker
    reg r_pending_sof;

    // 4-Stage Output Shift Register (Queue)
    // Sized to handle the maximum burst of 4 pixels (RAW10)
    reg [MAX_PIXEL_WIDTH-1:0] sr_data  [0:3];
    reg                       sr_valid [0:3];
    reg                       sr_sof   [0:3];
    reg                       sr_eol   [0:3];

    // =========================================================================
    // Load Enable Logic
    // =========================================================================
    // Triggers when a full pixel (or group of pixels) is completely assembled.
    wire load_en = i_rx_valid && (
        is_raw8 ||
        (is_2byte && byte_cnt == 3'd1) ||
        (is_3byte && byte_cnt == 3'd2) ||
        (is_raw10 && byte_cnt == 3'd4)
    );

    // =========================================================================
    // Byte Accumulator Process
    // =========================================================================
    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            byte_cnt <= 3'd0;
            r_byte0 <= 8'h00; r_byte1 <= 8'h00; 
            r_byte2 <= 8'h00; r_byte3 <= 8'h00;
        end else if (i_rx_valid) begin
            if (load_en) begin
                byte_cnt <= 3'd0; // Reset counter for the next pixel/group
            end else begin
                byte_cnt <= byte_cnt + 1'b1;
                case (byte_cnt)
                    3'd0: r_byte0 <= i_rx_data;
                    3'd1: r_byte1 <= i_rx_data;
                    3'd2: r_byte2 <= i_rx_data;
                    3'd3: r_byte3 <= i_rx_data;
                endcase
            end
        end
    end

    // =========================================================================
    // Output Shift Register & Formatting Logic
    // =========================================================================
    
    // Combinational bypass for SOF flag to prevent 1-cycle race conditions
    wire w_current_sof = r_pending_sof | i_rx_frame_start;

    integer i;
    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                sr_data[i]  <= 0;
                sr_valid[i] <= 0;
                sr_sof[i]   <= 0;
                sr_eol[i]   <= 0;
            end
            r_pending_sof <= 0;
        end else begin
            // 1. Track Frame Start Pulse
            if (i_rx_frame_start) begin
                // If loading right now, consume instantly. Otherwise, hold.
                if (load_en) r_pending_sof <= 1'b0; 
                else         r_pending_sof <= 1'b1;
            end 
            else if (load_en) begin
                r_pending_sof <= 1'b0; // Clears as it attaches to the first pixel
            end

            // 2. Load or Shift
            if (load_en) begin
                // OVERWRITE Shift Register with fully constructed pixel(s)
                if (is_raw8) begin
                    sr_data[0]  <= i_rx_data;
                    sr_valid[0] <= 1'b1;
                    sr_sof[0]   <= w_current_sof; // Use combinational bypass
                    sr_eol[0]   <= i_rx_packet_done;
                    
                    sr_valid[1] <= 0; sr_valid[2] <= 0; sr_valid[3] <= 0;
                end
                else if (is_2byte) begin
                    sr_data[0]  <= {r_byte0, i_rx_data}; // MSB first
                    sr_valid[0] <= 1'b1;
                    sr_sof[0]   <= w_current_sof; // Use combinational bypass
                    sr_eol[0]   <= i_rx_packet_done;
                    
                    sr_valid[1] <= 0; sr_valid[2] <= 0; sr_valid[3] <= 0;
                end
                else if (is_3byte) begin
                    sr_data[0]  <= {r_byte0, r_byte1, i_rx_data}; // MSB first
                    sr_valid[0] <= 1'b1;
                    sr_sof[0]   <= w_current_sof; // Use combinational bypass
                    sr_eol[0]   <= i_rx_packet_done;
                    
                    sr_valid[1] <= 0; sr_valid[2] <= 0; sr_valid[3] <= 0;
                end
                else if (is_raw10) begin
                    // RAW10 Reverse Gearbox: Extract LSBs and map to buffered MSBs
                    sr_data[0] <= {r_byte0, i_rx_data[1:0]};
                    sr_data[1] <= {r_byte1, i_rx_data[3:2]};
                    sr_data[2] <= {r_byte2, i_rx_data[5:4]};
                    sr_data[3] <= {r_byte3, i_rx_data[7:6]};
                    
                    sr_valid[0] <= 1'b1; sr_valid[1] <= 1'b1; 
                    sr_valid[2] <= 1'b1; sr_valid[3] <= 1'b1;
                    
                    sr_sof[0] <= w_current_sof; // Use combinational bypass
                    sr_sof[1] <= 0; sr_sof[2] <= 0; sr_sof[3] <= 0;
                    
                    sr_eol[0] <= 0; sr_eol[1] <= 0; sr_eol[2] <= 0;
                    sr_eol[3] <= i_rx_packet_done; // EOL maps to the 4th output pixel
                end
            end 
            else if (sr_valid[0]) begin
                // SHIFT DOWN to burst out pixels (used heavily by RAW10)
                sr_data[0] <= sr_data[1]; sr_data[1] <= sr_data[2]; 
                sr_data[2] <= sr_data[3]; sr_data[3] <= 0;
                
                sr_valid[0] <= sr_valid[1]; sr_valid[1] <= sr_valid[2]; 
                sr_valid[2] <= sr_valid[3]; sr_valid[3] <= 0;
                
                sr_sof[0] <= sr_sof[1]; sr_sof[1] <= sr_sof[2]; 
                sr_sof[2] <= sr_sof[3]; sr_sof[3] <= 0;
                
                sr_eol[0] <= sr_eol[1]; sr_eol[1] <= sr_eol[2]; 
                sr_eol[2] <= sr_eol[3]; sr_eol[3] <= 0;
            end
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign o_native_data  = sr_data[0];
    assign o_native_valid = sr_valid[0];
    assign o_native_sof   = sr_sof[0];
    assign o_native_eol   = sr_eol[0];

endmodule