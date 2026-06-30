`timescale 1ns / 1ps

// ============================================================================
// File Name    : async_fifo_ppi_tx.v
// Project      : MIPI CSI-2 Controller IP
// Description  : Parameterized Asynchronous FIFO for PPI Transmitter.
//                Facilitates safe Clock Domain Crossing (CDC) between the 
//                System Clock Domain and the MIPI TX Byte Clock Domain.
// Features     : 
//                - Multi-flop synchronization for Gray-coded pointers.
//                - Binary-to-Gray conversion to prevent multi-bit CDC glitches.
//                - Fully parameterized Data Width and FIFO Depth.
//                - DFT-Compliant: Memory array is fully resettable to support 
//                  Scan Chain insertion and ATPG tool compatibility.
// ============================================================================

module async_fifo_ppi_tx #(  
    parameter WIDTH = 8,
    parameter DEPTH = 16
)(
    // -------------------------------------------------------------------------
    // Write Domain Interface (Source)
    // -------------------------------------------------------------------------
    input  wire              i_wr_clk,
    input  wire              i_wr_rst_n, 
    input  wire              i_wr_en,
    input  wire [WIDTH-1:0]  i_din,
    output wire              o_full,

    // -------------------------------------------------------------------------
    // Read Domain Interface (Destination)
    // -------------------------------------------------------------------------
    input  wire              i_rd_clk,
    input  wire              i_rd_rst_n, 
    input  wire              i_rd_en,
    output wire [WIDTH-1:0]  o_dout,
    output wire              o_empty
);

    // =========================================================================
    // Local Parameters & Internal Signals
    // =========================================================================
    // Address width calculation based on parameterized FIFO depth
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Internal Memory Array (Dual-Port RAM configuration)
    reg [WIDTH-1:0] mem [DEPTH-1:0];

    // Pointers: ADDR_WIDTH+1 is used for Full/Empty wrap-around detection
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray; 
    
    // Synchronizer Flip-Flops (2-stage synchronizers for CDC safety)
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Combinational next-state pointers for faster evaluation
    wire [ADDR_WIDTH:0] wr_ptr_next = wr_ptr + 1;
    wire [ADDR_WIDTH:0] rd_ptr_next = rd_ptr + 1;
    
    // Loop variable for DFT-compliant memory reset
    integer j;

    // =========================================================================
    // 1. Write Domain Logic
    // Description: Handles pointer incrementing and Binary-to-Gray conversion.
    //              Binary pointers are used for memory addressing, while Gray 
    //              pointers are used for safe clock domain crossing.
    // =========================================================================
    always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
        if (!i_wr_rst_n) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0; 
        end else if (i_wr_en && !o_full) begin
            wr_ptr <= wr_ptr_next;
            // Binary to Gray conversion: XOR shifted value with original
            wr_ptr_gray <= wr_ptr_next ^ (wr_ptr_next >> 1); 
        end
    end

    // =========================================================================
    // 2. Memory Write Operation (DFT-Compliant)
    // Description: Writes data to the memory array. Incorporates a full reset 
    //              loop to synthesize into standard D-Flip-Flops with reset 
    //              pins, ensuring compatibility with DFT scan chains.
    // =========================================================================
    always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
        if (!i_wr_rst_n) begin
            for (j = 0; j < DEPTH; j = j + 1) begin
                mem[j] <= {WIDTH{1'b0}};
            end
        end else if (i_wr_en && !o_full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= i_din;
        end
    end

    // =========================================================================
    // 3. Read Domain Logic
    // Description: Manages the read pointer and converts it to Gray code.
    // =========================================================================
    always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
        if (!i_rd_rst_n) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
        end else if (i_rd_en && !o_empty) begin
            rd_ptr <= rd_ptr_next;
            // Binary to Gray conversion
            rd_ptr_gray <= rd_ptr_next ^ (rd_ptr_next >> 1); 
        end
    end
    
    // Continuous assignment for data output, gated by the 'o_empty' flag
    // to prevent reading garbage/stale data.
    assign o_dout = (o_empty) ? {WIDTH{1'b0}} : mem[rd_ptr[ADDR_WIDTH-1:0]];

    // =========================================================================
    // 4. Clock Domain Crossing (CDC) Synchronizers
    // Description: Synchronizes Gray-coded pointers into the opposite domain
    //              using standard 2-FF synchronizers to mitigate metastability.
    // =========================================================================
    
    // Synchronize Read Pointer into Write Clock Domain
    always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
        if (!i_wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Synchronize Write Pointer into Read Clock Domain
    always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
        if (!i_rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // =========================================================================
    // 5. Status Flag Generation
    // Description: 
    //   - o_full : True if write pointer matches synchronized read pointer, 
    //              accounting for the wrap-around bit in the Gray domain.
    //   - o_empty: True if read pointer matches synchronized write pointer.
    // =========================================================================
    assign o_full  = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign o_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

endmodule

