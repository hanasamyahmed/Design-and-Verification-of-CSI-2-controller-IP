`timescale 1ns / 1ps

// ============================================================================
// File Name   : lane_merger.v
// Project     : MIPI CSI Controller IP
// Description : Data Lane Merger / Serializer.
//               Responsible for aggregating byte streams from 1, 2, or 4 
//               parallel MIPI lanes back into a single sequential byte stream.
//               Implements a pull-based architecture with internal buffering 
//               to ensure continuous, stall-free data delivery to the MAC layer.
// ============================================================================

module lane_merger (
    // ---------------------------------------------------------
    // System Clock & Reset
    // ---------------------------------------------------------
    input  wire        i_clk,
    input  wire        i_rst_n,
    
    // ---------------------------------------------------------
    // Configuration & Control Signals
    // ---------------------------------------------------------
    input  wire [2:0]  i_active_lanes, 
    input  wire        i_packet_active, 
    input  wire        i_rx_ready,     

    // -------------------------------------------------------------------------
    // Parallel Data Inputs (From PPI RX FIFOs)
    // ---------------------------------------------------------
    input  wire [7:0]  i_lane0_data, i_lane1_data, i_lane2_data, i_lane3_data,
    input  wire        i_lane0_vld,  i_lane1_vld,  i_lane2_vld,  i_lane3_vld, 

    // -------------------------------------------------------------------------
    // Serial Data Outputs & FIFO Pull Control
    // ---------------------------------------------------------
    output wire        o_pull_data,
    output reg  [7:0]  o_merged_data,
    output reg         o_merged_valid
);

    // Internal Buffers & FSM Registers
    reg [7:0] r_buf1, r_buf2, r_buf3;
    reg [3:1] r_vld_buf; 
    reg [1:0] r_count;
    reg [1:0] next_count; 
    
    reg [2:0] startup_delay;
    reg       r_is_active;

    // =========================================================================
    // 1. Startup Delay & Active State Controller
    // Description: Introduces a brief initialization delay (3 cycles) upon 
    //              receiving 'i_rx_ready' before starting to pull data. This 
    //              ensures data alignment and prevents premature reads.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            startup_delay <= 3'd3;
            r_is_active   <= 1'b0;
        end else if (!i_packet_active && (r_count == 2'd0) && !o_pull_data) begin
            startup_delay <= 3'd3;
            r_is_active   <= 1'b0;
        end else if (i_rx_ready && !r_is_active) begin
            if (startup_delay > 0) startup_delay <= startup_delay - 1;
            else                   r_is_active <= 1'b1;
        end
    end

    // Pull condition: Only assert read enable when active, in FSM state 0, and RX is ready
    assign o_pull_data = r_is_active && (r_count == 2'd0) && i_rx_ready;
    
    // =========================================================================
    // 2. Output Multiplexer FSM (Next State Logic)
    // Description: Determines the sequence of outputting lanes based on the 
    //              active lane configuration (1, 2, or 4 lanes). Loops back 
    //              to state 0 to fetch the next parallel word.
    // =========================================================================
    always @(*) begin
        next_count = r_count;
        case (r_count)
            2'd0: if (o_pull_data && i_active_lanes > 1) next_count = 2'd1;
            2'd1: if (i_active_lanes > 2) next_count = 2'd2; else next_count = 2'd0;
            2'd2: if (i_active_lanes > 3) next_count = 2'd3; else next_count = 2'd0;
            2'd3: next_count = 2'd0;
            default: next_count = 2'd0;
        endcase
    end

    // =========================================================================
    // 3. Datapath & Pipelined Buffering
    // Description: 
    //   - State 0: Outputs Lane 0 directly and concurrently buffers Lanes 1/2/3.
    //   - State 1/2/3: Streams the buffered data sequentially out to the MAC.
    //   This ensures zero dead-cycles when converting parallel to serial.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_count        <= 2'd0;
            o_merged_data  <= 8'h00; 
            o_merged_valid <= 1'b0;
            r_buf1 <= 8'h00; r_buf2 <= 8'h00; r_buf3 <= 8'h00;
            r_vld_buf <= 3'b000;
        end else if (!i_packet_active && (r_count == 2'd0) && !o_pull_data) begin
            r_count        <= 2'd0;
            o_merged_data  <= 8'h00; 
            o_merged_valid <= 1'b0;
        end else begin
            r_count <= next_count;
            case (r_count)
                2'd0: begin
                    if (o_pull_data) begin
                        // Directly output Lane 0
                        o_merged_data  <= i_lane0_vld ? i_lane0_data : 8'h00;
                        o_merged_valid <= i_lane0_vld; 
                        
                        // Buffer remaining lanes for upcoming cycles
                        r_buf1       <= i_lane1_data; 
                        r_vld_buf[1] <= i_lane1_vld;
                        r_buf2       <= i_lane2_data; 
                        r_vld_buf[2] <= i_lane2_vld;
                        r_buf3       <= i_lane3_data; 
                        r_vld_buf[3] <= i_lane3_vld;
                    end else begin
                        o_merged_valid <= 1'b0;
                        o_merged_data  <= 8'h00;
                    end
                end
                2'd1: begin
                    o_merged_data  <= r_vld_buf[1] ? r_buf1 : 8'h00; 
                    o_merged_valid <= r_vld_buf[1]; 
                end
                2'd2: begin
                    o_merged_data  <= r_vld_buf[2] ? r_buf2 : 8'h00; 
                    o_merged_valid <= r_vld_buf[2];
                end
                2'd3: begin
                    o_merged_data  <= r_vld_buf[3] ? r_buf3 : 8'h00; 
                    o_merged_valid <= r_vld_buf[3];
                end
            endcase
        end
    end
endmodule

