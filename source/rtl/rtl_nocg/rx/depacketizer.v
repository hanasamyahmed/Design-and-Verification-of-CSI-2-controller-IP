// =============================================================================
// Module Name : rx_depacketizer
// File Name   : rx_depacketizer.v
// Author      : Hana Samy
// Date        : June 2026
// Description : MIPI CSI-2 RX packet parser. Decodes incoming streaming byte data 
//               into Header, Payload, and Footer (CRC) packets based on the 
//               current FSM state. Includes ECC double-error abort quarantine 
//               and CRC configuration flags.
// =============================================================================

`timescale 1ns / 1ps

module rx_depacketizer (
    // Clock and Reset
    input  wire         i_clk,
    input  wire         i_rst_n,
    
    // Configuration
    input  wire         i_cfg_crc_en,
    
    // Input Stream (MIPI Byte-level interface)
    input  wire [7:0]   i_rx_data,
    input  wire         i_rx_valid,
    
    // Output to Unpacker (Payload Data Stream)
    output reg  [7:0]   o_pay_data,
    output reg          o_pay_valid,
    output reg          o_pay_last,
    output reg          o_pay_user,
    
    // Output to External ECC (Header Processing)
    output reg  [31:0]  o_ecc_hdr_data,
    output reg          o_hdr_captured,

    // ECC Feedback (Error Correction & Detection)
    input  wire [25:0]  i_ecc_corrected_header,
    input  wire         i_ecc_header_valid,
    input  wire         i_ecc_double_err,

    // Output to External CRC Calculation Unit
    output reg  [7:0]   o_crc_data,
    output reg          o_crc_valid,
    output reg          o_crc_start,
    output reg          o_crc_end
);

    // =========================================================================
    // FSM State Definitions
    // =========================================================================
    // ST_HEADER : Parsing packet header (4 bytes)
    // ST_PAYLOAD: Streaming packet payload data
    // ST_FOOTER : Processing packet footer (CRC/Checksum bytes)
    // ST_ABORT  : Quarantining state in response to fatal ECC double-bit errors
    localparam ST_HEADER  = 2'd0;
    localparam ST_PAYLOAD = 2'd1;
    localparam ST_FOOTER  = 2'd2;
    localparam ST_ABORT   = 2'd3; 

    reg [1:0] state, next_state;

    // =========================================================================
    // Internal Registers & Counters
    // =========================================================================
    reg [1:0]  hdr_cnt;       // Tracks header bytes received (0 to 3)
    reg [15:0] pay_cnt;       // Tracks payload bytes received against word_count
    reg        ftr_cnt;       // Tracks footer/CRC bytes received
    
    reg [31:0] hdr_shift_reg; // Shift register to assemble the 32-bit packet header
    reg [15:0] word_count;    // Word count extracted from packet header
    reg        frame_started; // Flag tracking if a Frame Start (FS) short packet occurred

    // =========================================================================
    // FSM Sequential Logic
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state          <= ST_HEADER;
            hdr_cnt        <= 2'd0;
            pay_cnt        <= 16'd0;
            ftr_cnt        <= 1'b0;
            hdr_shift_reg  <= 32'd0;
            word_count     <= 16'd0;
            o_ecc_hdr_data <= 32'd0;
            o_hdr_captured <= 1'b0;
            frame_started  <= 1'b0;
        end else begin
            // Synchronous reset paths with priority on fatal ECC faults
            if (i_ecc_double_err) begin
                state          <= ST_ABORT; 
                hdr_cnt        <= 2'd0;
                pay_cnt        <= 16'd0;
                ftr_cnt        <= 1'b0;
                o_hdr_captured <= 1'b0;
            end else begin
                state          <= next_state;
                o_hdr_captured <= 1'b0; // Default pulse clearing for header captured flag
            end

            // Latch corrected word count from ECC pipeline when valid
            if (i_ecc_header_valid) begin
                word_count <= i_ecc_corrected_header[23:8]; 
            end

            // Data Path Evaluation
            if (i_rx_valid && !i_ecc_double_err) begin
                case (state)
                    ST_HEADER: begin
                        // Assemble incoming serial bytes into a 32-bit header
                        hdr_shift_reg[hdr_cnt*8 +: 8] <= i_rx_data;
                        
                        if (hdr_cnt == 2'd3) begin
                            hdr_cnt        <= 2'd0;
                            o_ecc_hdr_data <= {i_rx_data, hdr_shift_reg[23:0]};
                            word_count     <= {hdr_shift_reg[23:16], hdr_shift_reg[15:8]};
                            
                            // Signal downstream logic if header maps to a long packet data type
                            if (hdr_shift_reg[5:4] != 2'b00)
                                o_hdr_captured <= 1'b1;

                            // Identify Frame Start (FS) short packet (Data Type = 0x00)
                            if (hdr_shift_reg[5:0] == 6'h00)
                                frame_started <= 1'b1;
                        end else begin
                            hdr_cnt <= hdr_cnt + 1'b1;
                        end
                    end
                    
                    ST_PAYLOAD: begin
                        // Clear frame start tracking on first payload transfer
                        if (pay_cnt == 16'd0) 
                            frame_started <= 1'b0;

                        // Reset payload byte counter upon reaching the expected word count limit
                        if (pay_cnt == word_count - 1'b1) 
                            pay_cnt <= 16'd0;
                        else                            
                            pay_cnt <= pay_cnt + 1'b1;
                    end
                    
                    ST_FOOTER: begin
                        // Toggle/reset footer byte counter for 2-byte CRC sequence
                        if (ftr_cnt == 1'b1) 
                            ftr_cnt <= 1'b0;
                        else                 
                            ftr_cnt <= ftr_cnt + 1'b1;
                    end
                    
                    ST_ABORT: begin
                        // Quarantine state: swallow erroneous streaming bursts safely without counter corruption
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // FSM Next State Logic (Combinational)
    // =========================================================================
    always @* begin
        next_state = state;
        
        if (i_ecc_double_err) begin
            next_state = ST_ABORT;
        end else begin
            case (state)
                ST_HEADER: begin
                    // Remain in header state until 4 full bytes are clocked in
                    if (i_rx_valid && hdr_cnt == 2'd3) begin
                        if (hdr_shift_reg[5:4] == 2'b00) begin
                            next_state = ST_HEADER; // Short Packet format retains header state
                        end 
                        else if ({hdr_shift_reg[23:16], hdr_shift_reg[15:8]} == 16'd0) begin
                            // Skip payload parsing if Word Count is zero
                            next_state = i_cfg_crc_en ? ST_FOOTER : ST_HEADER;
                        end 
                        else begin
                            next_state = ST_PAYLOAD;
                        end
                    end
                end
                
                ST_PAYLOAD: begin
                    // Transition to footer/CRC or back to header once payload completes
                    if (i_rx_valid && pay_cnt == word_count - 1'b1) begin
                        next_state = i_cfg_crc_en ? ST_FOOTER : ST_HEADER;
                    end
                end
                
                ST_FOOTER: begin 
                    // Return to Header search phase after consuming 2-byte CRC footer
                    if (i_rx_valid && ftr_cnt == 1'b1) 
                        next_state = ST_HEADER;
                end
                
                ST_ABORT: begin
                    // Release quarantine and return to IDLE/HEADER search once upstream transmission stops
                    if (!i_rx_valid) 
                        next_state = ST_HEADER;
                end
            endcase
        end
    end

    // =========================================================================
    // Output Combinational Logic
    // =========================================================================
    always @* begin
        // Default assignments to prevent latch inference
        o_pay_data  = i_rx_data;
        o_pay_valid = 1'b0;
        o_pay_last  = 1'b0;
        o_pay_user  = 1'b0;

        o_crc_data  = i_rx_data;
        o_crc_valid = 1'b0;
        o_crc_start = 1'b0;
        o_crc_end   = 1'b0;

        // Valid payload stream conditions
        if (i_rx_valid) begin
            if (state == ST_PAYLOAD) begin
                o_pay_valid = 1'b1;
                o_pay_user  = (pay_cnt == 16'd0) && frame_started; // Asserted on first payload byte of a valid frame
                o_pay_last  = (pay_cnt == word_count - 1'b1);      // Asserted on final payload byte

                o_crc_valid = 1'b1;
                o_crc_start = (pay_cnt == 16'd0);
                o_crc_end   = (pay_cnt == word_count - 1'b1); 
            end
        end

        // Pass streaming bytes to CRC checker during footer window
        if (state == ST_FOOTER) begin
            o_crc_valid = 1'b1;
        end
    end
endmodule