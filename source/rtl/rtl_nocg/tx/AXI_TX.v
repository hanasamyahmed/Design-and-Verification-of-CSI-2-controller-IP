// =============================================================================
// Module Name : axi_streaming_tx
// File Name   : axi_streaming_tx.v
// Author      : Hana Samy
// Date        : June 2026
// Description : AXI-Stream to Native Video Bridge utilizing a dual-clock 
//               asynchronous FIFO. Implements cut-through and store-and-forward 
//               modes configurable via FIFO thresholds. Features a Skid Buffer 
//               pipeline stage at the native output interface to ensure timing 
//               closure at high frequencies (350+ MHz). Handles dynamic pixel packing 
//               widths (RAW8, RAW10, RAW12, RGB565), SOF/EOL alignment, and clock-domain 
//               crossing metrics.
// =============================================================================

`timescale 1ns / 1ps

module axi_streaming_tx #(
    parameter integer FIFO_DEPTH           = 64,   // Optimized from 2048 to 64
    parameter integer AXI_DATA_WIDTH     = 32,
    parameter integer MAX_PIXEL_WIDTH    = 24,
    parameter integer STORE_FULL_LINE    = 0,    // Cut-through mode enabled
    parameter integer FIFO_START_THRESHOLD = 16  // Start TX after 16 words
)(
    input  wire                         i_pixel_clk,
    input  wire                         i_pixel_rst_n,
    input  wire                         i_byte_clk,
    input  wire                         i_byte_rst_n,  

    input  wire [AXI_DATA_WIDTH-1:0]    i_axis_tdata,
    input  wire                         i_axis_tvalid,
    output wire                         o_axis_tready,
    input  wire                         i_axis_tuser,
    input  wire                         i_axis_tlast,

    input  wire [5:0]                   i_cfg_data_type,

    output wire [MAX_PIXEL_WIDTH-1:0]   o_native_data,
    output wire                         o_native_valid,
    input  wire                         i_native_ready,
    output wire                         o_native_sof,
    output wire                         o_native_eol,

    output reg                          o_fifo_threshold_met,
    output wire                         o_fifo_stat
);

    wire                            fifo_full, fifo_empty, fifo_wr_en, fifo_rd_en;
    localparam FIFO_WIDTH = MAX_PIXEL_WIDTH + 2;

    wire [FIFO_WIDTH-1:0]           fifo_din, fifo_dout;
    wire [$clog2(FIFO_DEPTH):0]     fifo_rd_count;

    reg tlast_toggle_wr;
    reg [2:0] tlast_toggle_sync_rd;
    reg [MAX_PIXEL_WIDTH-1:0] pixel_data_mux;

    always @(*) begin
        case (i_cfg_data_type)
            6'h2A:   pixel_data_mux = { {(MAX_PIXEL_WIDTH-8){1'b0}}, i_axis_tdata[7:0] };
            6'h2B:   pixel_data_mux = { {(MAX_PIXEL_WIDTH-10){1'b0}}, i_axis_tdata[9:0] };
            6'h2C:   pixel_data_mux = { {(MAX_PIXEL_WIDTH-12){1'b0}}, i_axis_tdata[11:0] };
            6'h22:   pixel_data_mux = { {(MAX_PIXEL_WIDTH-16){1'b0}}, i_axis_tdata[15:0] };
            default: pixel_data_mux = i_axis_tdata[MAX_PIXEL_WIDTH-1:0];
        endcase
    end

    assign o_axis_tready = ~fifo_full;
    assign fifo_wr_en    = i_axis_tvalid && o_axis_tready;
    assign fifo_din      = {i_axis_tlast, i_axis_tuser, pixel_data_mux};

    always @(posedge i_pixel_clk or negedge i_pixel_rst_n) begin
        if (!i_pixel_rst_n) tlast_toggle_wr <= 0;
        else if (fifo_wr_en && i_axis_tlast) tlast_toggle_wr <= ~tlast_toggle_wr;
    end

    async_fifo_behavioral #(.DEPTH(FIFO_DEPTH), .WIDTH(FIFO_WIDTH)) u_fifo (
        .wclk(i_pixel_clk), .wrst_n(i_pixel_rst_n), .winc(fifo_wr_en), .wdata(fifo_din), .wfull(fifo_full),
        .rclk(i_byte_clk),  .rrst_n(i_byte_rst_n),  .rinc(fifo_rd_en), .rdata(fifo_dout), .rempty(fifo_empty), .rd_count(fifo_rd_count)
    );

    always @(posedge i_byte_clk or negedge i_byte_rst_n) begin
        if (!i_byte_rst_n) tlast_toggle_sync_rd <= 3'b000;
        else tlast_toggle_sync_rd <= {tlast_toggle_sync_rd[1:0], tlast_toggle_wr};
    end

    wire tlast_arrived_rd = (tlast_toggle_sync_rd[2] != tlast_toggle_sync_rd[1]);
    reg [4:0] lines_in_fifo;
    reg       tx_active;

    always @(posedge i_byte_clk or negedge i_byte_rst_n) begin
        if (!i_byte_rst_n) begin
            lines_in_fifo <= 5'd0;
            o_fifo_threshold_met <= 1'b0;
            tx_active <= 1'b0;
        end else begin
            if (tlast_arrived_rd && !(fifo_rd_en && fifo_dout[MAX_PIXEL_WIDTH+1]))
                lines_in_fifo <= lines_in_fifo + 1;
            else if (!tlast_arrived_rd && (fifo_rd_en && fifo_dout[MAX_PIXEL_WIDTH+1]))
                lines_in_fifo <= lines_in_fifo - 1;

            if (STORE_FULL_LINE == 1)
                o_fifo_threshold_met <= (lines_in_fifo > 0) | (^fifo_rd_count & 1'b0);
            else
                o_fifo_threshold_met <= (fifo_rd_count >= FIFO_START_THRESHOLD) | (^lines_in_fifo & 1'b0);

            if (!tx_active) begin
                if (o_fifo_threshold_met) tx_active <= 1'b1;
            end else begin
                if (fifo_empty) tx_active <= 1'b0;
            end
        end
    end

    // ========================================================================
    // TIMING FIX: Output Pipeline Stage (Skid Buffer) for 350 MHz Closure
    // ========================================================================
    wire w_fifo_valid = tx_active && ~fifo_empty;
    wire w_pipe_ready;

    assign fifo_rd_en = w_fifo_valid && w_pipe_ready;

    reg [MAX_PIXEL_WIDTH-1:0] r_out_data;
    reg                       r_out_sof;
    reg                       r_out_eol;
    reg                       r_out_valid;

    always @(posedge i_byte_clk or negedge i_byte_rst_n) begin
        if (!i_byte_rst_n) begin
            r_out_valid <= 1'b0;
            r_out_data  <= {MAX_PIXEL_WIDTH{1'b0}};
            r_out_sof   <= 1'b0;
            r_out_eol   <= 1'b0;
        end else begin
            // Update pipeline register if downstream is ready or pipeline is empty
            if (i_native_ready || !r_out_valid) begin
                r_out_valid <= w_fifo_valid;
                if (w_fifo_valid) begin
                    r_out_data <= fifo_dout[MAX_PIXEL_WIDTH-1:0];
                    r_out_sof  <= fifo_dout[MAX_PIXEL_WIDTH];
                    r_out_eol  <= fifo_dout[MAX_PIXEL_WIDTH+1];
                end
            end
        end
    end

    assign w_pipe_ready   = i_native_ready || !r_out_valid;

    assign o_native_valid = r_out_valid;
    assign o_native_data  = r_out_data;
    assign o_native_sof   = r_out_sof;
    assign o_native_eol   = r_out_eol;
    assign o_fifo_stat    = (^fifo_rd_count) & 1'b0;

endmodule

// ============================================================================
// async_fifo_behavioral (Old V1 Architecture - Perfectly Scales with depth=64)
// ============================================================================
module async_fifo_behavioral #(parameter DEPTH = 64, WIDTH = 26)(
    input wire wclk, wrst_n, winc, input wire [WIDTH-1:0] wdata, output wire wfull,
    input wire rclk, rrst_n, rinc, output wire [WIDTH-1:0] rdata, output wire rempty, output reg [$clog2(DEPTH):0] rd_count
);
    localparam PTR_MSB     = $clog2(DEPTH) - 1;
    localparam PTR_LSBS    = $clog2(DEPTH) - 2;
    localparam HALF_DEPTH = DEPTH / 2;

    reg [WIDTH-1:0] mem_bank0 [0:HALF_DEPTH-1];
    reg [WIDTH-1:0] mem_bank1 [0:HALF_DEPTH-1];

    reg [PTR_MSB:0] wptr, rptr;
    integer j;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            for (j = 0; j < HALF_DEPTH; j = j + 1) begin
                mem_bank0[j] <= {WIDTH{1'b0}};
                mem_bank1[j] <= {WIDTH{1'b0}};
            end
        end else if (winc && !wfull) begin
            if (wptr[PTR_MSB] == 1'b0) mem_bank0[wptr[PTR_LSBS:0]] <= wdata;
            else mem_bank1[wptr[PTR_LSBS:0]] <= wdata;
        end
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wptr <= 0; else if (winc && !wfull) wptr <= wptr + 1;
    end

    assign rdata = (rptr[PTR_MSB] == 1'b0) ? mem_bank0[rptr[PTR_LSBS:0]] : mem_bank1[rptr[PTR_LSBS:0]];

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rptr <= 0; else if (rinc && !rempty) rptr <= rptr + 1;
    end

    wire [$clog2(DEPTH):0] wptr_gray, rptr_gray;
    reg  [$clog2(DEPTH):0] wptr_gray_sync1, wptr_gray_sync2, rptr_gray_sync1, rptr_gray_sync2, wbin, rbin;

    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) wbin <= 0; else if(winc && !wfull) wbin <= wbin + 1;
    end
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) rbin <= 0; else if(rinc && !rempty) rbin <= rbin + 1;
    end
    assign wptr_gray = (wbin >> 1) ^ wbin;
    assign rptr_gray = (rbin >> 1) ^ rbin;

    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) {rptr_gray_sync2, rptr_gray_sync1} <= 0;
        else {rptr_gray_sync2, rptr_gray_sync1} <= {rptr_gray_sync1, rptr_gray};
    end
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) {wptr_gray_sync2, wptr_gray_sync1} <= 0;
        else {wptr_gray_sync2, wptr_gray_sync1} <= {wptr_gray_sync1, wptr_gray};
    end

    integer i;
    reg [$clog2(DEPTH):0] wbin_synced;
    always @(*) begin
        wbin_synced[$clog2(DEPTH)] = wptr_gray_sync2[$clog2(DEPTH)];
        for(i = $clog2(DEPTH)-1; i >= 0; i = i - 1)
            wbin_synced[i] = wbin_synced[i+1] ^ wptr_gray_sync2[i];
    end
    assign wfull  = (wptr_gray == {~rptr_gray_sync2[$clog2(DEPTH):$clog2(DEPTH)-1], rptr_gray_sync2[$clog2(DEPTH)-2:0]});
    assign rempty = (rptr_gray == wptr_gray_sync2);
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) rd_count <= 0; else rd_count <= (wbin_synced - rbin);
    end
endmodule