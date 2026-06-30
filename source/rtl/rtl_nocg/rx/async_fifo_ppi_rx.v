`timescale 1ns / 1ps

// ============================================================================
// File Name   : async_fifo_ppi_rx.v
// Project     : MIPI CSI Controller IP
// Description : Parameterized Asynchronous FIFO for PPI Receiver.
//               Facilitates safe data transfer from the MIPI D-PHY High-Speed 
//               Byte Clock domain to the internal System Clock domain.
// Features    : 
//               - 2-stage (Double-Flop) synchronizers for metastability relief.
//               - Gray-coded pointer crossing to prevent multi-bit transitions.
//               - Fully parameterized width and depth for IP flexibility.
// ============================================================================

module async_fifo_ppi_rx #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
)(
    // -------------------------------------------------------------------------
    // Write Domain Interface (Source: D-PHY Clock Domain)
    // ---------------------------------------------------------
    input  wire              i_wr_clk,     // D-PHY Byte Clock
    input  wire              i_wr_rst_n,   // Reset synchronized to wr_clk
    input  wire              i_wr_en,      // Write enable
    input  wire [WIDTH-1:0]  i_din,        // Data input from PPI
    output wire              o_full,       // FIFO full flag

    // -------------------------------------------------------------------------
    // Read Domain Interface (Destination: System Clock Domain)
    // ---------------------------------------------------------
    input  wire              i_rd_clk,     // Internal System Clock
    input  wire              i_rd_rst_n,   // Reset synchronized to rd_clk
    input  wire              i_rd_en,      // Read enable from Lane Merger
    output wire [WIDTH-1:0]  o_dout,       // Data output to Lane Merger
    output wire              o_empty       // FIFO empty flag
);

    // Address width calculation
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Internal Memory and Pointer Registers
    reg [WIDTH-1:0] mem [DEPTH-1:0];
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray; 
    
    // Cross-Domain Synchronizers (2-Stage / Double-Flop)
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Pointer increments
    wire [ADDR_WIDTH:0] wr_ptr_next = wr_ptr + 1;
    wire [ADDR_WIDTH:0] rd_ptr_next = rd_ptr + 1;
    integer j;
    // =========================================================================
    // 1. Write Domain Logic
    // Description: Updates the write pointer and its Gray-coded version.
    //              Writes are only performed when 'i_wr_en' is active and FIFO 
    //              is not full. Binary pointer is used for memory addressing.
    // =========================================================================
    always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
        if (!i_wr_rst_n) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
        end else if (i_wr_en && !o_full) begin
            wr_ptr <= wr_ptr_next;
            wr_ptr_gray <= wr_ptr_next ^ (wr_ptr_next >> 1); 
        end
    end

    // Synthesis of the Memory Array (Register-based)
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
    // 2. Read Domain Logic
    // Description: Updates the read pointer and converts it to Gray code.
    //              Ensures safe data output only when FIFO is not empty.
    //              Gray pointers are used to safely pass the pointer across domains.
    // =========================================================================
    always @(posedge i_rd_clk or negedge i_rd_rst_n) begin
        if (!i_rd_rst_n) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
        end else if (i_rd_en && !o_empty) begin
            rd_ptr <= rd_ptr_next;
            rd_ptr_gray <= rd_ptr_next ^ (rd_ptr_next >> 1); 
        end
    end
    
    // Data Output Assignment (zeroed if empty to prevent data leakage)
    assign o_dout = (o_empty) ? {WIDTH{1'b0}} : mem[rd_ptr[ADDR_WIDTH-1:0]];

    // =========================================================================
    // 3. Clock Domain Crossing (CDC) Synchronizers
    // Description: Synchronizes pointers between the two asynchronous domains.
    //              Gray coding ensures only one bit changes per transition, 
    //              which prevents incorrect intermediate values during sampling.
    // =========================================================================
    
    // Cross Read Pointer into Write Domain
    always @(posedge i_wr_clk or negedge i_wr_rst_n) begin
        if (!i_wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Cross Write Pointer into Read Domain
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
    // 4. Status Flag Generation
    // Description: Compares Gray-coded pointers to determine FIFO status.
    //              - o_empty: True if read pointer equals synchronized write pointer.
    //              - o_full : True if write pointer MSBs are inverted relative to 
    //                         synchronized read pointer (indicating wrap-around).
    // =========================================================================
    assign o_full  = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign o_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
    

endmodule
