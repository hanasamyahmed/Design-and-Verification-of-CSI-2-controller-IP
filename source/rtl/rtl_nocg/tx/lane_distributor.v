`timescale 1ns / 1ps

// ============================================================================
// File Name   : lane_distributor.v
// Project     : MIPI CSI Controller IP
// Description : Data Lane Distributor / Demultiplexer.
//               Responsible for taking a serial byte stream from the packetizer
//               and distributing it across 1, 2, or 4 parallel MIPI lanes
//               based on the active lane configuration. Includes flush logic 
//               for partial cycles and early look-ahead request generation.
// ============================================================================

module lane_distributor (
    // -------------------------------------------------------------------------
    // System Clock & Reset
    // ---------------------------------------------------------
    input  wire        i_clk,
    input  wire        i_rst_n,
    
    // -------------------------------------------------------------------------
    // Input Data Stream (From Packetizer)
    // ---------------------------------------------------------
    input  wire [7:0]  i_pkt_data,
    input  wire        i_pkt_vld,
    input  wire [1:0]  i_cfg_active_lanes,    
    
    // -------------------------------------------------------------------------
    // Parallel Data Outputs (To Scramblers/TX)
    // ---------------------------------------------------------
    output reg  [7:0]  o_lane0_data,
    output reg  [7:0]  o_lane1_data,
    output reg  [7:0]  o_lane2_data,
    output reg  [7:0]  o_lane3_data,
    
    // -------------------------------------------------------------------------
    // Parallel Valid Outputs
    // ---------------------------------------------------------
    output reg         o_lane0_vld,
    output reg         o_lane1_vld,
    output reg         o_lane2_vld,
    output reg         o_lane3_vld,
    
    // -------------------------------------------------------------------------
    // PHY Wake-up Control
    // ---------------------------------------------------------
    output wire        o_req_hs
);

    reg  [1:0] r_lane_cnt;         
    wire [1:0] w_demux_sel;        
    wire       w_master_valid;     
    
    reg        r_pkt_vld_q;        
    wire       w_flush_en;         

    // =========================================================================
    // 1. Programmable Lane Counter
    // Description: Tracks the current target lane for the incoming byte.
    //              Wraps around dynamically based on 'i_cfg_active_lanes'.
    //              Resets automatically upon a flush event (end of packet).
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_lane_cnt <= 2'd0;
        end else begin
            if (i_pkt_vld) begin
                if (r_lane_cnt == i_cfg_active_lanes) begin
                    r_lane_cnt <= 2'd0; 
                end else begin
                    r_lane_cnt <= r_lane_cnt + 1'b1; 
                end
            end else if (w_flush_en) begin
                r_lane_cnt <= 2'd0; 
            end
        end
    end

    assign w_demux_sel    = r_lane_cnt;
    assign w_master_valid = (i_pkt_vld && (r_lane_cnt == i_cfg_active_lanes));

    // =========================================================================
    // 2. Byte Demultiplexer & Data Registers
    // Description: Routes the incoming byte to the appropriate lane register
    //              based on the current state of the demux selector.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_lane0_data <= 8'd0; o_lane1_data <= 8'd0;
            o_lane2_data <= 8'd0; o_lane3_data <= 8'd0;
        end else if (i_pkt_vld) begin
            case (w_demux_sel)
                2'd0: o_lane0_data <= i_pkt_data;
                2'd1: o_lane1_data <= i_pkt_data;
                2'd2: o_lane2_data <= i_pkt_data;
                2'd3: o_lane3_data <= i_pkt_data;
            endcase
        end
    end

    // =========================================================================
    // 3. Valid Generation & Flush Controller
    // Description: Manages the assertion of valid signals for the parallel lanes.
    //              - Normal Operation: Asserts valids when a full set is ready.
    //              - Flush Operation: Safely pushes out partially filled lanes
    //                if the packet terminates mid-cycle.
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_pkt_vld_q <= 1'b0;
        else          r_pkt_vld_q <= i_pkt_vld;
    end

    assign w_flush_en = (r_pkt_vld_q && !i_pkt_vld && (r_lane_cnt != 2'd0));

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_lane0_vld <= 1'b0; o_lane1_vld <= 1'b0;
            o_lane2_vld <= 1'b0; o_lane3_vld <= 1'b0;
        end else begin
            if (w_master_valid) begin
                o_lane0_vld <= 1'b1;
                o_lane1_vld <= (i_cfg_active_lanes >= 2'd1);
                o_lane2_vld <= (i_cfg_active_lanes >= 2'd2);
                o_lane3_vld <= (i_cfg_active_lanes == 2'd3);
            end else if (w_flush_en) begin
                o_lane0_vld <= 1'b1; 
                o_lane1_vld <= (r_lane_cnt > 2'd1);
                o_lane2_vld <= (r_lane_cnt > 2'd2);
                o_lane3_vld <= 1'b0; 
            end else begin
                o_lane0_vld <= 1'b0; o_lane1_vld <= 1'b0;
                o_lane2_vld <= 1'b0; o_lane3_vld <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. Look-ahead High-Speed Request Generation
    // Description: Asserts an early 'o_req_hs' to transition the D-PHY to HS
    //              mode. Covers packet start, flush duration, and active data
    //              driving periods.
    // =========================================================================
    assign o_req_hs = i_pkt_vld || r_pkt_vld_q || o_lane0_vld;

endmodule

