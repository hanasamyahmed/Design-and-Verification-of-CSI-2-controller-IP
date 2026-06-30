// =============================================================================
// Module Name : csi2_packetizer
// File Name   : csi2_packetizer.v
// Author      : Hana Samy
// Date        : June 2026
// Description : Packetizes D-PHY payload streams into MIPI CSI-2 formatted packets,
//               supporting long and short packets, dynamic data types, virtual 
//               channels, ECC, and optional CRC framing bytes.
// =============================================================================

`timescale 1ns / 1ps

module csi2_packetizer (
    // Clocks & Resets
    input  wire        i_byte_clk,
    input  wire        i_rst_n,

    // Upstream Interface
    input  wire [7:0]  i_p2b_data,
    input  wire        i_p2b_valid,
    input  wire        i_p2b_line_start,
    input  wire        i_p2b_packet_done,
    input  wire        i_p2b_frame_start,
    input  wire        i_p2b_frame_end,

    // Configuration (From Register File)
    input  wire        i_cfg_crc_en,    // CRC Enable signal
    input  wire [15:0] i_cfg_wc,
    input  wire [5:0]  i_cfg_data_type,
    input  wire [1:0]  i_cfg_vc_id,

    // External Combinational & Sequential Inputs
    input  wire [5:0]  i_ecc,       
    input  wire [7:0]  i_crc_data,  

    // Downstream Interface (To D-PHY)
    output reg  [7:0]  o_tx_data,
    output reg         o_tx_valid,
    output wire        o_frame_end
    // output wire     o_line_start  // Uncomment if needed
);

    // =========================================================================
    // 1. Internal Signals & Parameters
    // =========================================================================
    
    localparam S_IDLE       = 3'd0;
    localparam S_HEADER     = 3'd1; 
    localparam S_PAYLOAD    = 3'd2; 
    localparam S_FOOTER_1   = 3'd3; 
    localparam S_FOOTER_2   = 3'd4; 
    localparam S_SHORT_PKT  = 3'd5; 

    reg [2:0] state, next_state;
    reg [2:0] byte_cnt;
    
    // Latched ID for Short Packets
    reg [7:0] r_short_di;

    // Pipeline Signals (10 Stages)
    reg [10:0] pipeline [0:9]; 
    wire [7:0] pipe_out_data;
    wire       pipe_out_valid;
    wire       pipe_out_last; 
    wire       pipe_out_fe ;

    wire [7:0] header_di_long;
    
    reg ls_reg1, ls_reg2, ls_reg3, ls_reg4, ls_reg5;
    reg fe_reg1, fe_reg2, fe_reg3; // REMOVED fe_reg4

    // =========================================================================
    // 2. Pipeline Delay (Data Path)
    // =========================================================================
    
    integer k;
    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (k = 0; k < 10; k = k + 1) begin
                pipeline[k] <= 11'd0;
            end
        end
        else begin
            pipeline[0] <= {i_p2b_frame_end, i_p2b_packet_done, i_p2b_valid, i_p2b_data};
            for (k = 1; k < 10; k = k + 1) begin
                pipeline[k] <= pipeline[k-1];
            end
        end
    end
    
    assign {pipe_out_fe, pipe_out_last, pipe_out_valid, pipe_out_data} = pipeline[9];

    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            ls_reg1 <= 1'b0;
            ls_reg2 <= 1'b0;
            ls_reg3 <= 1'b0;
            ls_reg4 <= 1'b0;
            ls_reg5 <= 1'b0;
        end else begin
            ls_reg1 <= i_p2b_line_start;
            ls_reg2 <= ls_reg1;
            ls_reg3 <= ls_reg2;
            ls_reg4 <= ls_reg3;
            ls_reg5 <= ls_reg4;
        end
    end

    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            fe_reg1 <= 1'b0;
            fe_reg2 <= 1'b0;
            fe_reg3 <= 1'b0;
        end else begin
            fe_reg1 <= pipe_out_fe;
            fe_reg2 <= fe_reg1;
            fe_reg3 <= fe_reg2;
        end
    end
    
    assign o_frame_end = fe_reg3;

    // =========================================================================
    // 3. Header Formatting
    // =========================================================================
    
    assign header_di_long = {i_cfg_vc_id, i_cfg_data_type};

    // =========================================================================
    // 4. FSM Controller (Control Path)
    // =========================================================================

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (i_p2b_frame_start || o_frame_end)
                    next_state = S_SHORT_PKT;
                else if (ls_reg5)
                    next_state = S_HEADER;
            end

            S_HEADER: begin
                if (byte_cnt == 3)
                    next_state = S_PAYLOAD;
            end

            S_PAYLOAD: begin
                if (pipe_out_valid && pipe_out_last) begin
                    // Skip footer if CRC is disabled
                    if (i_cfg_crc_en)
                        next_state = S_FOOTER_1;
                    else
                        next_state = S_IDLE; 
                end
            end

            S_FOOTER_1: next_state = S_FOOTER_2;
            S_FOOTER_2: next_state = S_IDLE;
            
            S_SHORT_PKT: begin
                if (byte_cnt == 3)
                    next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // Sequential Logic (Outputs & Counters)
    always @(posedge i_byte_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state      <= S_IDLE;
            byte_cnt   <= 3'd0;
            o_tx_valid <= 1'b0;
            o_tx_data  <= 8'd0;
            r_short_di <= 8'h00;
        end
        else begin
            state      <= next_state;
            o_tx_valid <= 1'b0; 

            case (state)
                S_IDLE: begin
                    byte_cnt <= 3'd0;
                    
                    if (i_p2b_frame_start)
                        r_short_di <= {i_cfg_vc_id, 6'h00};
                    else if (o_frame_end)
                        r_short_di <= {i_cfg_vc_id, 6'h01};
                end

                S_HEADER: begin
                    o_tx_valid <= 1'b1;
                    byte_cnt   <= byte_cnt + 1'b1;
                    case (byte_cnt)
                        3'd0: o_tx_data <= header_di_long; 
                        3'd1: o_tx_data <= i_cfg_wc[7:0];  
                        3'd2: o_tx_data <= i_cfg_wc[15:8]; 
                        3'd3: o_tx_data <= {2'b00, i_ecc}; 
                    endcase
                end

                S_PAYLOAD: begin
                    o_tx_valid <= pipe_out_valid;
                    o_tx_data  <= pipe_out_data;
                    byte_cnt   <= 3'd0; 
                end

                S_FOOTER_1: begin
                    o_tx_valid <= 1'b1;
                    o_tx_data  <= i_crc_data; 
                end

                S_FOOTER_2: begin
                    o_tx_valid <= 1'b1;
                    o_tx_data  <= i_crc_data; 
                end
                
                S_SHORT_PKT: begin
                    o_tx_valid <= 1'b1;
                    byte_cnt   <= byte_cnt + 1'b1;
                    case (byte_cnt)
                        3'd0: o_tx_data <= r_short_di;    
                        3'd1: o_tx_data <= 8'h00;          
                        3'd2: o_tx_data <= 8'h00;          
                        3'd3: o_tx_data <= {2'b00, i_ecc}; 
                    endcase
                end
            endcase
        end
    end

endmodule