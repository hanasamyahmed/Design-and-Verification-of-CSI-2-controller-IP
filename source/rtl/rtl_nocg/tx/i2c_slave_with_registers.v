`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module Name   : i2c_slave_with_registers
// Description   : I2C Slave Interface with 16-bit Register Addressing
//                 
//                 Implements a standard I2C slave controller designed to bridge 
//                 the Camera Control Interface (CCI) to the internal register 
//                 bank of the CSI-2 Transmitter. It supports 7-bit slave addressing, 
//                 16-bit internal register addressing, and 8-bit data payload 
//                 reads/writes with auto-incrementing address capability.
//
// Author        : Mohamed Zaher Fouda
// Architecture  : - 3-stage synchronizers for SCL/SDA to prevent metastability.
//                 - Edge detection for START/STOP conditions.
//                 - 3-Block FSM for robust I2C protocol state management.
//                 - Tristate SDA control for acknowledgment and read data.
//-----------------------------------------------------------------------------

module i2c_slave_with_registers #(
    // -- Configurable Parameters --
    parameter SLAVE_ADDR = 7'h50        // 7-bit I2C Target Address
)(
    // -- Clocks & Resets --
    input  wire        i_clk,           // High-speed system clock for oversampling
    input  wire        i_rst_n,         // Active-low asynchronous reset

    // -- I2C Physical Interface --
    input  wire        i_SCL,           // Serial Clock Line (Input only for slave)
    inout  wire        io_sda,          // Serial Data Line (Bidirectional open-drain)

    // -- Register Bank Interface --
    output reg         o_reg_wr_en,     // Register write enable strobe
    output reg         o_reg_rd_en,     // Register read enable strobe
    output reg  [15:0] o_reg_addr,      // 16-bit Register Address
    output reg  [7:0]  o_reg_wdata,     // 8-bit Write Data (To Register Bank)
    input  wire [7:0]  i_reg_rdata      // 8-bit Read Data (From Register Bank)
);

    //=========================================================================
    // STATE ENCODING (Local Parameters)
    //=========================================================================
    localparam [3:0] 
        ST_IDLE      = 4'd0,  // Bus is idle, waiting for START
        ST_ADDR      = 4'd1,  // Receiving 7-bit Device Address + R/W bit
        ST_ADDR_ACK  = 4'd2,  // Acknowledging Device Address
        ST_REG_HI    = 4'd3,  // Receiving Upper 8 bits of Register Address
        ST_HI_ACK    = 4'd4,  // Acknowledging Upper Address Byte
        ST_REG_LO    = 4'd5,  // Receiving Lower 8 bits of Register Address
        ST_LO_ACK    = 4'd6,  // Acknowledging Lower Address Byte
        ST_WDATA     = 4'd7,  // Receiving 8-bit Write Data
        ST_WDATA_ACK = 4'd8,  // Acknowledging Write Data
        ST_RDATA     = 4'd9,  // Transmitting 8-bit Read Data
        ST_RDATA_ACK = 4'd10; // Waiting for Master to ACK/NACK Read Data

    //=========================================================================
    // INTERNAL SIGNALS
    //=========================================================================
    reg  [3:0] state, next_state;
    reg        rw_flag, r_ack, r_rd_drive, tx_load;
    reg  [7:0] tx_shift, reg_hi;
    
    // Synchronizer registers
    reg        scl_d1, scl_d2, scl_d3;
    reg        sda_d1, sda_d2, sda_d3;
    
    // Data path registers
    reg  [3:0] bit_cnt;
    reg  [7:0] rx_shift;
    reg        byte_done;

    //=========================================================================
    // SDA TRISTATE CONTROL
    //=========================================================================
    // Drive SDA low for ACK or when transmitting a '0' during read cycles.
    // Otherwise, release the line (High-Z) to be pulled up externally.
    wire r_sda_drive = r_ack | (r_rd_drive & ~tx_shift[7]);
    assign io_sda = r_sda_drive ? 1'b0 : 1'bz;

    //=========================================================================
    // EDGE & CONDITION DETECTORS
    //=========================================================================
    wire scl_rise  =  scl_d2 & ~scl_d3;
    wire scl_fall  = ~scl_d2 &  scl_d3;
    
    // START: SDA falls while SCL is high
    wire start_det = ~sda_d2 &  sda_d3 & scl_d2;
    // STOP: SDA rises while SCL is high
    wire stop_det  =  sda_d2 & ~sda_d3 & scl_d2;

    //=========================================================================
    // 3-STAGE SYNCHRONIZERS
    //=========================================================================
    // Mitigates metastability issues from the asynchronous I2C bus signals
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            {scl_d1, scl_d2, scl_d3} <= 3'b111;
            {sda_d1, sda_d2, sda_d3} <= 3'b111;
        end else begin
            scl_d1 <= i_SCL;   scl_d2 <= scl_d1;  scl_d3 <= scl_d2;
            sda_d1 <= io_sda;  sda_d2 <= sda_d1;  sda_d3 <= sda_d2;
        end
    end

    //=========================================================================
    // BIT COUNTER & RECEIVE SHIFT REGISTER
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            bit_cnt   <= 4'd0;
            rx_shift  <= 8'h00;
            byte_done <= 1'b0;
        end else if (start_det || stop_det) begin
            // Reset counters on START or STOP conditions
            bit_cnt   <= 4'd0;
            rx_shift  <= 8'h00;
            byte_done <= 1'b0;
        end else begin
            // Flag byte completion on the 8th rising edge (index 7)
            byte_done <= (scl_rise && bit_cnt == 4'd7);
            
            // Sample SDA on SCL rising edge for data bits
            if (scl_rise && bit_cnt < 4'd8)
                rx_shift <= {rx_shift[6:0], sda_d2};
            
            // Manage bit tracking (0 to 8, where 8 is the ACK/NACK bit)
            if (scl_rise && bit_cnt < 4'd9)
                bit_cnt <= bit_cnt + 4'd1;
            else if (scl_fall && bit_cnt == 4'd9)
                bit_cnt <= 4'd0;
        end
    end

    //=========================================================================
    // FSM BLOCK 1: STATE REGISTER
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin 
            state <= ST_IDLE;
        end else if (stop_det) begin   
            state <= ST_IDLE;
        end else if (start_det) begin  
            state <= ST_ADDR;
        end else begin                 
            state <= next_state;
        end
    end

    //=========================================================================
    // FSM BLOCK 2: NEXT STATE LOGIC
    //=========================================================================
    always @(*) begin
        next_state = state; // Default assignment prevents latches
        
        case (state)
            ST_ADDR:      if (byte_done) next_state = (rx_shift[7:1] == SLAVE_ADDR) ? ST_ADDR_ACK : ST_IDLE;
            ST_ADDR_ACK:  if (scl_fall && bit_cnt == 4'd9) next_state = rw_flag ? ST_RDATA : ST_REG_HI;
            
            ST_REG_HI:    if (byte_done) next_state = ST_HI_ACK;
            ST_HI_ACK:    if (scl_fall && bit_cnt == 4'd9) next_state = ST_REG_LO;
            
            ST_REG_LO:    if (byte_done) next_state = ST_LO_ACK;
            ST_LO_ACK:    if (scl_fall && bit_cnt == 4'd9) next_state = rw_flag ? ST_RDATA : ST_WDATA;
            
            ST_WDATA:     if (byte_done) next_state = ST_WDATA_ACK;
            ST_WDATA_ACK: if (scl_fall && bit_cnt == 4'd9) next_state = ST_WDATA;
            
            ST_RDATA:     if (byte_done) next_state = ST_RDATA_ACK;
            ST_RDATA_ACK: if (scl_rise && bit_cnt == 4'd8) next_state = (sda_d2 == 1'b0) ? ST_RDATA : ST_IDLE;
            
            default:      next_state = ST_IDLE;
        endcase
    end

    //=========================================================================
    // FSM BLOCK 3: SEQUENTIAL OUTPUTS & CONTROL LOGIC
    //=========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            {rw_flag, r_ack, r_rd_drive, tx_load} <= 4'b0;
            {tx_shift, reg_hi, o_reg_addr, o_reg_wdata} <= 0;
            {o_reg_wr_en, o_reg_rd_en} <= 2'b0;
        end else begin
            // Default strobes
            o_reg_wr_en <= 1'b0; 
            o_reg_rd_en <= 1'b0; 
            tx_load     <= 1'b0;

            // Handle Transmit Shift Register for Read operations
            if (tx_load) 
                tx_shift <= i_reg_rdata;
            else if (state == ST_RDATA && scl_fall && bit_cnt >= 1 && bit_cnt <= 7)
                tx_shift <= {tx_shift[6:0], 1'b0};

            // Handle ACK generation on 9th clock cycle
            if (scl_fall) begin
                if (bit_cnt == 8) begin
                    case (next_state) 
                        ST_ADDR_ACK, ST_HI_ACK, ST_LO_ACK, ST_WDATA_ACK: r_ack <= 1'b1; 
                        default: r_ack <= 1'b0; 
                    endcase
                end else if (bit_cnt == 9 || bit_cnt == 0) begin
                    r_ack <= 1'b0;
                end
            end

            // Main datapath routing and control sequencing
            case (state)
                ST_ADDR: begin
                    if (byte_done) rw_flag <= rx_shift[0];
                end
                
                ST_ADDR_ACK: begin
                    if (scl_fall && bit_cnt == 9 && rw_flag) begin 
                        o_reg_rd_en <= 1'b1; 
                        tx_load     <= 1'b1; 
                        r_rd_drive  <= 1'b1; 
                    end
                end
                
                ST_REG_HI: begin
                    if (byte_done) reg_hi <= rx_shift;
                end
                
                ST_REG_LO: begin
                    if (byte_done) o_reg_addr <= {reg_hi, rx_shift};
                end
                
                ST_LO_ACK: begin
                    if (scl_fall && bit_cnt == 9 && rw_flag) begin 
                        o_reg_rd_en <= 1'b1; 
                        tx_load     <= 1'b1; 
                        r_rd_drive  <= 1'b1; 
                    end
                end
                
                ST_WDATA: begin
                    if (byte_done) begin 
                        o_reg_wdata <= rx_shift; 
                        o_reg_wr_en <= 1'b1; 
                    end
                end
                
                ST_WDATA_ACK: begin
                    if (scl_fall && bit_cnt == 9) begin
                        o_reg_addr <= o_reg_addr + 1'b1; // Auto-increment address
                    end
                end
                
                ST_RDATA: begin
                    if (byte_done) r_rd_drive <= 1'b0; // Release bus for Master to ACK/NACK
                end
                
                ST_RDATA_ACK: begin
                    if (scl_rise && bit_cnt == 8 && sda_d2 == 1'b0) begin // If Master ACKs
                        o_reg_addr  <= o_reg_addr + 1'b1; // Auto-increment address
                        o_reg_rd_en <= 1'b1; 
                        tx_load     <= 1'b1; 
                        r_rd_drive  <= 1'b1; 
                    end
                end
            endcase
        end
    end
endmodule
