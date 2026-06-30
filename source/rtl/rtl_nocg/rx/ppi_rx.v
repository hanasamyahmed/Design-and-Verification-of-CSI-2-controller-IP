`timescale 1ns / 1ps

// ============================================================================
// File Name   : ppi_rx.v
// Project     : MIPI CSI Controller IP
// Description : Protocol-to-PHY Interface (PPI) Receiver Module.
//               Responsible for interfacing the MIPI D-PHY with the digital 
//               controller. Manages 4-lane High-Speed (HS) data reception, 
//               Clock Domain Crossing (CDC) using Asynchronous FIFOs, and 
//               glitch-free error flag synchronization.
// ============================================================================

module ppi_rx (
    // -------------------------------------------------------------------------
    // System Clocks and Resets
    // ---------------------------------------------------------
    input  wire        i_clk_sys,    
    input  wire        i_rst_n_sys, 
    input  wire        i_rst_n_rx,  

    // -------------------------------------------------------------------------
    // MIPI D-PHY High-Speed RX Clock
    // ---------------------------------------------------------
    input  wire        i_RxByteClkHS, 
    
    // -------------------------------------------------------------------------
    // High-Speed Data Signals (From PHY)
    // ---------------------------------------------------------
    input  wire [7:0]  i_RxDataHS_0, i_RxDataHS_1, i_RxDataHS_2, i_RxDataHS_3,
    input  wire        i_RxValidHS_0, i_RxValidHS_1, i_RxValidHS_2, i_RxValidHS_3,
    input  wire        i_RxActiveHS_0, i_RxActiveHS_1, i_RxActiveHS_2, i_RxActiveHS_3,
    input  wire        i_RxSyncHS_0, i_RxSyncHS_1, i_RxSyncHS_2, i_RxSyncHS_3,

    // -------------------------------------------------------------------------
    // MIPI D-PHY PPI RX Control & Error Signals (From PHY)
    // ---------------------------------------------------------
    input  wire        i_Shutdown,
    input  wire        i_Stopstate_0, i_Stopstate_1, i_Stopstate_2, i_Stopstate_3,
    input  wire        i_RxUlpmEsc_0, i_RxUlpmEsc_1, i_RxUlpmEsc_2, i_RxUlpmEsc_3,
    
    input  wire        i_ErrSotHS_0, i_ErrSotHS_1, i_ErrSotHS_2, i_ErrSotHS_3,
    input  wire        i_ErrSotSyncHS_0, i_ErrSotSyncHS_1, i_ErrSotSyncHS_2, i_ErrSotSyncHS_3,
    input  wire        i_ErrControl_0, i_ErrControl_1, i_ErrControl_2, i_ErrControl_3,
    input  wire        i_ErrEsc_0, i_ErrEsc_1, i_ErrEsc_2, i_ErrEsc_3,

    // -------------------------------------------------------------------------
    // Internal Interface (To Controller / Lane Merger)
    // ---------------------------------------------------------
    input  wire        i_lane0_rd_en, i_lane1_rd_en, i_lane2_rd_en, i_lane3_rd_en,
    
    output wire [7:0]  o_lane0_data,  o_lane1_data,  o_lane2_data,  o_lane3_data,
    output wire        o_lane0_valid, o_lane1_valid, o_lane2_valid, o_lane3_valid,
    
    output wire        o_packet_active,
    output wire        o_rx_ready,
    output wire        o_rx_error_flag // Interrput to the System
);

    // =========================================================================
    // CIL Error Handler Logic (100% Glitch-Free CDC)
    // Concept: Aggregates multiple asynchronous error sources, captures them 
    //          in the source domain, and safely crosses them using a 2-flop sync.
    // =========================================================================
    wire w_rx_error_comb = i_ErrSotHS_0 | i_ErrSotSyncHS_0 | i_ErrControl_0 | i_ErrEsc_0 |
                           i_ErrSotHS_1 | i_ErrSotSyncHS_1 | i_ErrControl_1 | i_ErrEsc_1 |
                           i_ErrSotHS_2 | i_ErrSotSyncHS_2 | i_ErrControl_2 | i_ErrEsc_2 |
                           i_ErrSotHS_3 | i_ErrSotSyncHS_3 | i_ErrControl_3 | i_ErrEsc_3 ;

    // Step 1: Register the combined error in the SOURCE domain (RX Clock) to prevent glitches
    // Made it STICKY to prevent Data Loss in fast-to-slow crossing
    reg r_rx_error_src_domain;
    always @(posedge i_RxByteClkHS or negedge i_rst_n_rx) begin
        if (!i_rst_n_rx) begin
            r_rx_error_src_domain <= 1'b0;
        end else begin
            // Sticky Error: Latch the error high so the System Clock NEVER misses it
            r_rx_error_src_domain <= r_rx_error_src_domain | w_rx_error_comb;
        end
    end

    // Step 2: Synchronize the stable signal to the DESTINATION domain (System Clock)
    reg [1:0] r_error_sync;
    always @(posedge i_clk_sys or negedge i_rst_n_sys) begin
        if (!i_rst_n_sys) begin
            r_error_sync <= 2'b00;
        end else begin
            r_error_sync <= {r_error_sync[0], r_rx_error_src_domain};
        end
    end
    assign o_rx_error_flag = r_error_sync[1]; // Safely synced to System Clock

    // =========================================================================
    // RX Data Path Logic
    // Architecture: 4 Independent Asynchronous FIFOs to handle Clock Domain 
    //               Crossing (CDC) for the payload data from the PHY clock 
    //               domain to the core system clock domain.
    // =========================================================================
    wire w_wr_en_0 = i_RxValidHS_0 & i_RxActiveHS_0;
    wire w_wr_en_1 = i_RxValidHS_1 & i_RxActiveHS_1;
    wire w_wr_en_2 = i_RxValidHS_2 & i_RxActiveHS_2;
    wire w_wr_en_3 = i_RxValidHS_3 & i_RxActiveHS_3;

    wire w_empty_0, w_empty_1, w_empty_2, w_empty_3;
    wire [7:0] w_raw_0, w_raw_1, w_raw_2, w_raw_3;
    wire w_fifo_full_0, w_fifo_full_1, w_fifo_full_2, w_fifo_full_3;

    // Safe read enable prevents underflow in the FIFOs
    wire w_safe_rd_0 = i_lane0_rd_en & ~w_empty_0;
    wire w_safe_rd_1 = i_lane1_rd_en & ~w_empty_1;
    wire w_safe_rd_2 = i_lane2_rd_en & ~w_empty_2;
    wire w_safe_rd_3 = i_lane3_rd_en & ~w_empty_3;

    async_fifo_ppi_rx #(.WIDTH(8), .DEPTH(16)) u_fifo_l0 (
        .i_wr_clk(i_RxByteClkHS), .i_wr_rst_n(i_rst_n_rx),
        .i_rd_clk(i_clk_sys), .i_rd_rst_n(i_rst_n_sys),
        .i_wr_en(w_wr_en_0), .i_din(i_RxDataHS_0), .i_rd_en(w_safe_rd_0),
        .o_dout(w_raw_0), .o_empty(w_empty_0), .o_full(w_fifo_full_0)
    );

    async_fifo_ppi_rx #(.WIDTH(8), .DEPTH(16)) u_fifo_l1 (
        .i_wr_clk(i_RxByteClkHS), .i_wr_rst_n(i_rst_n_rx),
        .i_rd_clk(i_clk_sys), .i_rd_rst_n(i_rst_n_sys),
        .i_wr_en(w_wr_en_1), .i_din(i_RxDataHS_1), .i_rd_en(w_safe_rd_1),
        .o_dout(w_raw_1), .o_empty(w_empty_1), .o_full(w_fifo_full_1)
    );

    async_fifo_ppi_rx #(.WIDTH(8), .DEPTH(16)) u_fifo_l2 (
        .i_wr_clk(i_RxByteClkHS), .i_wr_rst_n(i_rst_n_rx),
        .i_rd_clk(i_clk_sys), .i_rd_rst_n(i_rst_n_sys),
        .i_wr_en(w_wr_en_2), .i_din(i_RxDataHS_2), .i_rd_en(w_safe_rd_2),
        .o_dout(w_raw_2), .o_empty(w_empty_2), .o_full(w_fifo_full_2)
    );

    async_fifo_ppi_rx #(.WIDTH(8), .DEPTH(16)) u_fifo_l3 (
        .i_wr_clk(i_RxByteClkHS), .i_wr_rst_n(i_rst_n_rx),
        .i_rd_clk(i_clk_sys), .i_rd_rst_n(i_rst_n_sys),
        .i_wr_en(w_wr_en_3), .i_din(i_RxDataHS_3), .i_rd_en(w_safe_rd_3),
        .o_dout(w_raw_3), .o_empty(w_empty_3), .o_full(w_fifo_full_3)
    );

    // =========================================================================
    // Synthesis Optimization & Dummy Sink
    // Concept: AND-reduction with 1'b0 creates a safe structural sink for 
    //          unused interface signals, preventing synthesis tool warnings 
    //          and ensuring clean connectivity.
    // =========================================================================
    wire w_dummy_sink = &{1'b0, i_RxSyncHS_0, i_RxSyncHS_1, i_RxSyncHS_2, i_RxSyncHS_3,
                          w_fifo_full_0, w_fifo_full_1, w_fifo_full_2, w_fifo_full_3,
                          i_Shutdown, i_Stopstate_0, i_Stopstate_1, i_Stopstate_2, i_Stopstate_3,
                          i_RxUlpmEsc_0, i_RxUlpmEsc_1, i_RxUlpmEsc_2, i_RxUlpmEsc_3};

    // The dummy sink is logically OR'ed with o_rx_ready (X | 0 = X)
    assign o_rx_ready = (~w_empty_0) | w_dummy_sink; 

    // Output assignment & gating
    assign o_lane0_valid = ~w_empty_0 & i_lane0_rd_en;
    assign o_lane1_valid = ~w_empty_1 & i_lane1_rd_en;
    assign o_lane2_valid = ~w_empty_2 & i_lane2_rd_en;
    assign o_lane3_valid = ~w_empty_3 & i_lane3_rd_en;

    assign o_lane0_data = o_lane0_valid ? w_raw_0 : 8'h00;
    assign o_lane1_data = o_lane1_valid ? w_raw_1 : 8'h00;
    assign o_lane2_data = o_lane2_valid ? w_raw_2 : 8'h00;
    assign o_lane3_data = o_lane3_valid ? w_raw_3 : 8'h00;

    // =========================================================================
    // Packet Active State Machine (Hang Timer)
    // Concept: Maintains the active state of the packet for a set duration 
    //          (15 cycles) after the FIFO empties. This acts as a tolerance 
    //          buffer to prevent premature packet termination during inter-lane 
    //          skew or brief interruptions.
    // =========================================================================
    reg [3:0] rx_hang_timer;
    reg r_packet_active;
    
    always @(posedge i_clk_sys or negedge i_rst_n_sys) begin
        if (!i_rst_n_sys) begin
            r_packet_active <= 1'b0;
            rx_hang_timer   <= 4'd0;
        end else begin
            if (~w_empty_0) begin 
                r_packet_active <= 1'b1;
                rx_hang_timer   <= 4'd15; 
            end else if (rx_hang_timer > 0) begin
                rx_hang_timer   <= rx_hang_timer - 1;
            end else begin
                r_packet_active <= 1'b0;
            end
        end
    end
    assign o_packet_active = r_packet_active;

endmodule
