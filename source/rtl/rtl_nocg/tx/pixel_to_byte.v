// =============================================================================
// Module Name : pixel2byte_converter
// File Name   : pixel2byte_converter.v
// Author      : Hana Samy
// Date        : June 2026
// Description : Serializes wide parallel pixel data (Native/AXI-Stream TX) into 
//               byte-wide streams suited for MIPI D-PHY / Packetizer layers. 
//               Supports multiple data types (RAW8, YUV422, RGB565, RGB888) 
//               via simple serialization, and RAW10 via a specialized 5-byte 
//               Gearbox packing scheme. Handles packet delineation (SOF, EOL, 
//               EOF) and configurable Inter-Packet Gaps (IPG).
// =============================================================================

`timescale 1ns / 1ps

module pixel2byte_converter #(
    parameter INTER_PACKET_GAP = 8'd10 
)(
    // Clocks and Resets
    input  wire        i_byte_clk,
    input  wire        i_rst_n,

    // Configuration
    input  wire [5:0]  i_cfg_data_type,
    input  wire [15:0] i_frame_num_lines, 

    // Native Input (AXI Streaming-TX)
    input  wire [23:0] i_native_data,
    input  wire        i_native_valid,
    output reg         o_native_ready,
    input  wire        i_native_sof,
    input  wire        i_native_eol,

    // Byte Output (To D-PHY / Packetizer)
    output reg  [7:0]  o_byte_data,
    output reg         o_byte_valid,
    output reg         o_byte_frame_start,
    output reg         o_byte_frame_end,
    output reg         o_byte_line_start,
    output reg         o_byte_packet_done
);

    // =========================================================================
    // 1. Parameters & Configuration Decoding
    // =========================================================================
    localparam DT_RAW8   = 6'h2A;
    localparam DT_YUV422 = 6'h1E;
    localparam DT_RGB565 = 6'h22;
    localparam DT_RGB888 = 6'h24;
    localparam DT_RAW10  = 6'h2B;

    reg [2:0]  cfg_byte_ratio; 
    reg        cfg_mode_gearbox;
    reg        cfg_is_rgb565_yuv;

    always @(*) begin
        cfg_is_rgb565_yuv = 1'b0;
        case (i_cfg_data_type)
            DT_RAW8: begin
                cfg_byte_ratio   = 3'd1;
                cfg_mode_gearbox = 1'b0;
            end
            DT_YUV422, DT_RGB565: begin
                cfg_byte_ratio   = 3'd2;
                cfg_mode_gearbox = 1'b0;
                cfg_is_rgb565_yuv = 1'b1;
            end
            DT_RGB888: begin
                cfg_byte_ratio   = 3'd3;
                cfg_mode_gearbox = 1'b0;
            end
            DT_RAW10: begin
                cfg_byte_ratio   = 3'd5; 
                cfg_mode_gearbox = 1'b1;
            end
            default: begin 
                cfg_byte_ratio   = 3'd1;
                cfg_mode_gearbox = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // 2. FSM Next-State Logic (STARC05-2.11.3.1 Compliance)
    // =========================================================================
    reg [2:0]  state_cnt;
    reg [2:0]  next_state_cnt;
    
    reg [23:0] pixel_shift_reg;
    reg [7:0]  lsb_buffer;
    reg        active_eol_pending;
    reg        next_pixel_is_line_start;
    reg [15:0] line_count; 
    reg [7:0]  gap_cnt; 

    // Combinational block strictly for FSM next state
    always @(*) begin
        next_state_cnt = state_cnt; // Default: hold state

        if (gap_cnt == 0) begin
            if (!cfg_mode_gearbox) begin
                if (state_cnt == 0) begin
                    if (i_native_valid && i_cfg_data_type != DT_RAW8) begin
                        next_state_cnt = state_cnt + 1'b1;
                    end
                end else begin
                    if (state_cnt == (cfg_byte_ratio - 1)) begin
                        next_state_cnt = 3'd0;
                    end else begin
                        next_state_cnt = state_cnt + 1'b1;
                    end
                end
            end else begin
                // Gearbox mode
                if (state_cnt < 4) begin
                    if (i_native_valid) begin
                        if (state_cnt == 3'd3 || i_native_eol) begin
                            next_state_cnt = 3'd4;
                        end else begin
                            next_state_cnt = state_cnt + 1'b1;
                        end
                    end
                end else if (state_cnt == 4) begin
                    next_state_cnt = 3'd0;
                end
            end
        end
    end

    // =========================================================================
    // 3. Main Sequential Logic
    // =========================================================================
    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_cnt                <= 3'd0;
            o_byte_valid             <= 1'b0;
            o_byte_data              <= 8'd0;
            o_native_ready           <= 1'b1; 
            o_byte_frame_start       <= 1'b0;
            o_byte_frame_end         <= 1'b0;
            o_byte_line_start        <= 1'b0;
            o_byte_packet_done       <= 1'b0;
            lsb_buffer               <= 8'd0;
            pixel_shift_reg          <= 24'd0;
            active_eol_pending       <= 1'b0;
            next_pixel_is_line_start <= 1'b1;
            line_count               <= 16'd0;
            gap_cnt                  <= 8'd0; 
        end else begin
            // Default clears
            o_byte_frame_start <= 1'b0;
            o_byte_frame_end   <= 1'b0;
            o_byte_line_start  <= 1'b0;
            o_byte_packet_done <= 1'b0;
            o_byte_valid       <= 1'b0;
            
            // FSM State Update (Separated from Next State Logic)
            state_cnt <= next_state_cnt;

            if (gap_cnt > 0) begin
                gap_cnt <= gap_cnt - 1'b1;
                if (gap_cnt == 8'd1) o_native_ready <= 1'b1; 
                else                 o_native_ready <= 1'b0; 
            end 
            else begin
                // -----------------------------------------------------------------
                // MODE A: Simple Serialization (RAW8, RGB565, RGB888, YUV422)
                // -----------------------------------------------------------------
                if (!cfg_mode_gearbox) begin
                    if (state_cnt == 0) begin
                        if (i_native_valid) begin
                            o_native_ready     <= 1'b0;
                            o_byte_valid       <= 1'b1;
                            active_eol_pending <= i_native_eol;

                            // Frame/Line Start (STARC05-2.2.3.3 Fix: Merged double assignments)
                            if (i_native_sof) begin
                                o_byte_frame_start       <= 1'b1;
                                o_byte_line_start        <= 1'b1;
                                line_count               <= 16'd1;
                                next_pixel_is_line_start <= (i_cfg_data_type == DT_RAW8 && i_native_eol) ? 1'b1 : 1'b0;
                            end else if (next_pixel_is_line_start) begin
                                o_byte_line_start        <= 1'b1;
                                line_count               <= line_count + 16'd1;
                                next_pixel_is_line_start <= (i_cfg_data_type == DT_RAW8 && i_native_eol) ? 1'b1 : 1'b0;
                            end else if (i_cfg_data_type == DT_RAW8 && i_native_eol) begin
                                next_pixel_is_line_start <= 1'b1;
                            end

                            if (i_cfg_data_type == DT_RAW8) begin
                                o_byte_data <= i_native_data[7:0];
                                if (i_native_eol) begin
                                    o_byte_packet_done <= 1'b1;
                                    if (line_count == i_frame_num_lines)
                                        o_byte_frame_end <= 1'b1;
                                        
                                    if (INTER_PACKET_GAP > 0) begin
                                        gap_cnt        <= INTER_PACKET_GAP;
                                        o_native_ready <= 1'b0;
                                    end else o_native_ready <= 1'b1;
                                end else begin
                                    o_native_ready <= 1'b1;
                                end
                            end else begin
                                if (cfg_is_rgb565_yuv) begin
                                    o_byte_data     <= i_native_data[15:8];
                                    pixel_shift_reg <= {i_native_data[7:0],16'd0};
                                end else begin
                                    o_byte_data     <= i_native_data[23:16];
                                    pixel_shift_reg <= {i_native_data[15:0],8'd0};
                                end
                            end
                        end else begin
                            o_native_ready <= 1'b1;
                        end
                    end else begin
                        o_byte_valid    <= 1'b1;
                        o_byte_data     <= pixel_shift_reg[23:16];
                        pixel_shift_reg <= {pixel_shift_reg[15:0],8'd0};

                        if (state_cnt == (cfg_byte_ratio - 1)) begin
                            if (active_eol_pending) begin
                                o_byte_packet_done       <= 1'b1;
                                next_pixel_is_line_start <= 1'b1;
                                if (line_count == i_frame_num_lines)
                                    o_byte_frame_end <= 1'b1;
                                    
                                if (INTER_PACKET_GAP > 0) begin
                                    gap_cnt        <= INTER_PACKET_GAP;
                                    o_native_ready <= 1'b0;
                                end else o_native_ready <= 1'b1;
                            end else begin
                                o_native_ready <= 1'b1;
                            end
                        end else begin
                            o_native_ready <= 1'b0;
                        end
                    end
                end 
                // -----------------------------------------------------------------
                // MODE B: Gearbox (RAW10)
                // -----------------------------------------------------------------
                else begin
                    o_native_ready <= 1'b1; 
                    if (i_native_valid && state_cnt < 4) begin
                        o_byte_valid <= 1'b1;
                        o_byte_data  <= i_native_data[9:2]; 

                        case (state_cnt)
                            3'd0: lsb_buffer[1:0] <= i_native_data[1:0];
                            3'd1: lsb_buffer[3:2] <= i_native_data[1:0];
                            3'd2: lsb_buffer[5:4] <= i_native_data[1:0];
                            3'd3: lsb_buffer[7:6] <= i_native_data[1:0];
                        endcase

                        if (state_cnt == 0) begin
                            if (i_native_sof) begin
                                o_byte_frame_start       <= 1'b1;
                                o_byte_line_start        <= 1'b1;
                                line_count               <= 16'd1;
                                next_pixel_is_line_start <= 1'b0; 
                            end else if (next_pixel_is_line_start) begin
                                o_byte_line_start        <= 1'b1;
                                line_count               <= line_count + 16'd1;
                                next_pixel_is_line_start <= 1'b0;
                            end
                        end

                        if (i_native_eol) begin
                            active_eol_pending <= 1'b1;
                        end

                        if (state_cnt == 3'd3 || i_native_eol) begin
                            o_native_ready <= 1'b0; 
                        end
                    end 
                    else if (state_cnt == 4) begin
                        o_byte_valid <= 1'b1;
                        o_byte_data  <= lsb_buffer;

                        if (active_eol_pending) begin
                            o_byte_packet_done       <= 1'b1;
                            next_pixel_is_line_start <= 1'b1;
                            if (line_count == i_frame_num_lines)
                                o_byte_frame_end <= 1'b1;
                            active_eol_pending <= 1'b0;
                            
                            if (INTER_PACKET_GAP > 0) begin
                                gap_cnt        <= INTER_PACKET_GAP;
                                o_native_ready <= 1'b0;
                            end else o_native_ready <= 1'b1;
                        end else begin
                            o_native_ready <= 1'b1;
                        end
                    end
                end
            end 
        end 
    end

endmodule