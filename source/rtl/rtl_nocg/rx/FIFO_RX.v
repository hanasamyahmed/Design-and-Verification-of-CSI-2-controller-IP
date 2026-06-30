// =============================================================================
// Module Name : async_fifo_behavioral
// File Name   : async_fifo_behavioral.v
// Author      : Hana Samy 
// Date        : June 2026
// Description : Parameterized Asynchronous FIFO operating across two independent 
//               clock domains (wclk and rclk). Utilizes dual-bank memory splitting 
//               to optimize synthesis and Gray code pointer synchronization 
//               to prevent metastable conditions during cross-domain boundary crossings.
// =============================================================================

module async_fifo_behavioral #(
    parameter DEPTH = 64, 
    parameter WIDTH = 26
)(
    // Write Domain Interface
    input  wire                   wclk, 
    input  wire                   wrst_n, 
    input  wire                   winc, 
    input  wire      [WIDTH-1:0]  wdata, 
    output wire                   wfull,
    
    // Read Domain Interface
    input  wire                   rclk, 
    input  wire                   rrst_n, 
    input  wire                   rinc, 
    output wire      [WIDTH-1:0]  rdata, 
    output wire                   rempty, 
    output reg  [$clog2(DEPTH):0] rd_count
);
    // =========================================================================
    // Local Parameters & Memory Bank Configuration
    // =========================================================================
    localparam PTR_MSB     = $clog2(DEPTH) - 1;
    localparam PTR_LSBS    = $clog2(DEPTH) - 2;
    localparam HALF_DEPTH  = DEPTH / 2;

    // Split memory array architecture for synthesis optimization
    reg [WIDTH-1:0] mem_bank0 [0:HALF_DEPTH-1];
    reg [WIDTH-1:0] mem_bank1 [0:HALF_DEPTH-1];

    reg [PTR_MSB:0] wptr, rptr;
    integer j;

    // =========================================================================
    // Write Domain Memory Write Logic
    // =========================================================================
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            for (j = 0; j < HALF_DEPTH; j = j + 1) begin
                mem_bank0[j] <= {WIDTH{1'b0}};
                mem_bank1[j] <= {WIDTH{1'b0}};
            end
        end else if (winc && !wfull) begin
            // Bank selection based on the MSB of the write pointer
            if (wptr[PTR_MSB] == 1'b0) 
                mem_bank0[wptr[PTR_LSBS:0]] <= wdata;
            else 
                mem_bank1[wptr[PTR_LSBS:0]] <= wdata;
        end
    end

    // Write Pointer Increment Logic
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) 
            wptr <= 0; 
        else if (winc && !wfull) 
            wptr <= wptr + 1;
    end

    // =========================================================================
    // Read Domain Combinational Read Data Path
    // =========================================================================
    // Combinational read directly mapping to the selected memory bank
    assign rdata = (rptr[PTR_MSB] == 1'b0) ? mem_bank0[rptr[PTR_LSBS:0]] : mem_bank1[rptr[PTR_LSBS:0]];

    // Read Pointer Increment Logic
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) 
            rptr <= 0; 
        else if (rinc && !rempty) 
            rptr <= rptr + 1;
    end

    // =========================================================================
    // Gray Code Generation & Cross-Domain Synchronization
    // =========================================================================
    wire [$clog2(DEPTH):0] wptr_gray, rptr_gray;
    reg  [$clog2(DEPTH):0] wptr_gray_sync1, wptr_gray_sync2;
    reg  [$clog2(DEPTH):0] rptr_gray_sync1, rptr_gray_sync2;
    reg  [$clog2(DEPTH):0] wbin, rbin;

    // Binary pointer tracking within respective domains
    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) 
            wbin <= 0; 
        else if(winc && !wfull) 
            wbin <= wbin + 1;
    end
    
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) 
            rbin <= 0; 
        else if(rinc && !rempty) 
            rbin <= rbin + 1;
    end
    
    // Convert binary pointers to Gray code to ensure safe cross-clock boundary transfer
    assign wptr_gray = (wbin >> 1) ^ wbin;
    assign rptr_gray = (rbin >> 1) ^ rbin;

    // Double-register synchronizer stages to mitigate metastability (Write domain to Read domain)
    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) begin
            rptr_gray_sync1 <= 0;
            rptr_gray_sync2 <= 0;
        end else begin
            rptr_gray_sync1 <= rptr_gray;
            rptr_gray_sync2 <= rptr_gray_sync1;
        end
    end
    
    // Double-register synchronizer stages to mitigate metastability (Read domain to Write domain)
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) begin
            wptr_gray_sync1 <= 0;
            wptr_gray_sync2 <= 0;
        end else begin
            wptr_gray_sync1 <= wptr_gray;
            wptr_gray_sync2 <= wptr_gray_sync1;
        end
    end

    // =========================================================================
    // Status Flags & FIFO Occupancy Counter
    // =========================================================================
    integer i;
    reg [$clog2(DEPTH):0] wbin_synced;
    
    // Convert synchronized Gray pointer back to binary for depth/occupancy math
    always @(*) begin
        wbin_synced[$clog2(DEPTH)] = wptr_gray_sync2[$clog2(DEPTH)];
        for(i = $clog2(DEPTH)-1; i >= 0; i = i - 1)
            wbin_synced[i] = wbin_synced[i+1] ^ wptr_gray_sync2[i];
    end
    
    // Full condition: Gray pointers MSB and MSB-1 invert, while lower bits match
    assign wfull  = (wptr_gray == {~rptr_gray_sync2[$clog2(DEPTH):$clog2(DEPTH)-1], rptr_gray_sync2[$clog2(DEPTH)-2:0]});
    
    // Empty condition: Synchronized write pointer matches read pointer in Gray domain
    assign rempty = (rptr_gray == wptr_gray_sync2);
    
    // Calculate outstanding words inside the FIFO synchronous to the read clock
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) 
            rd_count <= 0; 
        else 
            rd_count <= (wbin_synced - rbin);
    end
endmodule