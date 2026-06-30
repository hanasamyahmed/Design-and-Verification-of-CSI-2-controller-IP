`timescale 1ns / 1ps

module mipi_tx_top (
    input  wire        sys_clk, pclk, pixel_clk, byte_clk,
    input  wire        sys_rst_n, preset_n, pixel_rst_n, byte_rst_n,
    input  wire [2:0]  cfg_active_lanes,
    input  wire [15:0] cfg_frame_lines,
    
    // APB
    input  wire        tx_apb_psel, tx_apb_penable, tx_apb_pwrite,
    input  wire [31:0] tx_apb_paddr, tx_apb_pwdata,
    output wire [31:0] tx_apb_prdata, output wire tx_apb_pready,
    
    // I2C
    input  wire        i2c_scl,
    inout  wire        i2c_sda,
    
    // AXI4-Stream
    input  wire [31:0] tx_axis_tdata,
    input  wire        tx_axis_tvalid, tx_axis_tuser, tx_axis_tlast,
    output wire        tx_axis_tready,
    
    // PPI TX
    output wire        ppi_tx_ClkRequestHS,
    input  wire        ppi_tx_ClkReadyHS, ppi_tx_ByteClkHS,
    output wire [3:0]  ppi_tx_RequestHS,
    input  wire [3:0]  ppi_tx_ReadyHS,
    output wire [7:0]  ppi_tx_DataHS_0, ppi_tx_DataHS_1, ppi_tx_DataHS_2, ppi_tx_DataHS_3,
    output wire        ppi_tx_ValidHS_0, ppi_tx_ValidHS_1, ppi_tx_ValidHS_2, ppi_tx_ValidHS_3,

    // Debug Taps
    output wire [7:0]  tx_lane0_data_out, tx_lane1_data_out, tx_lane2_data_out, tx_lane3_data_out,
    output wire        tx_lane0_vld_out, tx_lane1_vld_out, tx_lane2_vld_out, tx_lane3_vld_out,
    output wire        tx_req_hs_out
);

    // =========================================================================
    // 0. INTERNAL WIRES DECLARATION
    // =========================================================================
    wire w_tx_en, w_sw_rst, w_scram_enb, w_crc_enb;
    wire [15:0] w_cfg_wc, w_i2c_line_number;
    wire [1:0]  w_cfg_vc_id, w_cfg_active_lanes_i2c;
    wire [5:0]  w_cfg_data_type;
    wire w_pkt_valid, w_byte_pd;

    // =========================================================================
    // 1. Hardware Reset Synchronizers (Async Assert, Sync De-assert)
    // Description: Prevents recovery metastability by ensuring resets are 
    //              de-asserted synchronously to their respective clock domains.
    // Note: Separate reset ports are strictly maintained for ModelSim TB compatibility.
    // =========================================================================
    wire w_presetn_sync;
    reg [1:0] sync_regs_apb;
    always @(posedge pclk or negedge preset_n) begin
        if (!preset_n) sync_regs_apb <= 2'b00; else sync_regs_apb <= {sync_regs_apb[0], 1'b1};
    end
    assign w_presetn_sync = sync_regs_apb[1];

    wire w_rst_n_pix;
    reg [1:0] sync_regs_pix;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) sync_regs_pix <= 2'b00; else sync_regs_pix <= {sync_regs_pix[0], 1'b1};
    end
    assign w_rst_n_pix = sync_regs_pix[1];

    wire w_rst_n_sys;
    reg [1:0] sync_regs_sys;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) sync_regs_sys <= 2'b00; else sync_regs_sys <= {sync_regs_sys[0], 1'b1};
    end
    assign w_rst_n_sys = sync_regs_sys[1];

    wire w_rst_n_byte;
    reg [1:0] sync_regs_byte;
    always @(posedge byte_clk or negedge byte_rst_n) begin
        if (!byte_rst_n) sync_regs_byte <= 2'b00; else sync_regs_byte <= {sync_regs_byte[0], 1'b1};
    end
    assign w_rst_n_byte = sync_regs_byte[1];

    wire w_rst_n_tx;
    reg [1:0] sync_regs_tx;
    always @(posedge ppi_tx_ByteClkHS or negedge sys_rst_n) begin
        if (!sys_rst_n) sync_regs_tx <= 2'b00; else sync_regs_tx <= {sync_regs_tx[0], 1'b1};
    end
    assign w_rst_n_tx = sync_regs_tx[1];

    // =========================================================================
    // 2. Software Reset Injection (Safe De-assertion)
    // =========================================================================
    reg [1:0] sync_sw_rst_pix, sync_sw_rst_sys, sync_sw_rst_byte, sync_sw_rst_tx;
    
    always @(posedge pixel_clk or negedge w_rst_n_pix) begin
        if (!w_rst_n_pix) sync_sw_rst_pix <= 2'b00; else sync_sw_rst_pix <= {sync_sw_rst_pix[0], w_sw_rst};
    end
    always @(posedge sys_clk or negedge w_rst_n_sys) begin
        if (!w_rst_n_sys) sync_sw_rst_sys <= 2'b00; else sync_sw_rst_sys <= {sync_sw_rst_sys[0], w_sw_rst};
    end
    always @(posedge byte_clk or negedge w_rst_n_byte) begin
        if (!w_rst_n_byte) sync_sw_rst_byte <= 2'b00; else sync_sw_rst_byte <= {sync_sw_rst_byte[0], w_sw_rst};
    end
    always @(posedge ppi_tx_ByteClkHS or negedge w_rst_n_tx) begin
        if (!w_rst_n_tx) sync_sw_rst_tx <= 2'b00; else sync_sw_rst_tx <= {sync_sw_rst_tx[0], w_sw_rst};
    end

    wire final_rst_n_pix  = w_rst_n_pix  & ~sync_sw_rst_pix[1];
    wire final_rst_n_sys  = w_rst_n_sys  & ~sync_sw_rst_sys[1];
    wire final_rst_n_byte = w_rst_n_byte & ~sync_sw_rst_byte[1];
    wire final_rst_n_tx   = w_rst_n_tx   & ~sync_sw_rst_tx[1];

    // =========================================================================
    // 3. Control Signal Synchronizers
    // =========================================================================
    reg [1:0] pix_sync_tx_en;
    reg [5:0] pix_cfg_dt_sync1, pix_cfg_dt_sync2;
    
    always @(posedge pixel_clk or negedge final_rst_n_pix) begin
        if (!final_rst_n_pix) begin
            pix_sync_tx_en   <= 2'b00;
            pix_cfg_dt_sync1 <= 6'h2A;
            pix_cfg_dt_sync2 <= 6'h2A;
        end else begin
            pix_sync_tx_en   <= {pix_sync_tx_en[0], w_tx_en};
            pix_cfg_dt_sync1 <= w_cfg_data_type;
            pix_cfg_dt_sync2 <= pix_cfg_dt_sync1;
        end
    end

    reg [1:0] byte_sync_crc_enb;
    always @(posedge byte_clk or negedge final_rst_n_byte) begin
        if (!final_rst_n_byte) byte_sync_crc_enb <= 2'b00;
        else                   byte_sync_crc_enb <= {byte_sync_crc_enb[0], w_crc_enb};
    end

    // =========================================================================
    // 4. Dummy Wires Declaration
    // =========================================================================
    wire w_dummy_pslverr, w_dummy_tx_active, w_dummy_fifo_thresh, w_dummy_fifo_stat;
    wire w_dummy_frame_end, w_dummy_ulpm_clk;
    wire [3:0] w_dummy_req_esc, w_dummy_ulpm_esc;

    // =========================================================================
    // 5. Modules Instantiation
    // =========================================================================
    apb_csi2_tx_regfile u_regfile (
        .PCLK(pclk), .PRESETn(w_presetn_sync), .PSEL(tx_apb_psel), .PENABLE(tx_apb_penable), .PWRITE(tx_apb_pwrite), .PSTRB(4'hF),
        .PADDR(tx_apb_paddr), .PWDATA(tx_apb_pwdata), .PRDATA(tx_apb_prdata), .PREADY(tx_apb_pready),
        .PSLVERR(w_dummy_pslverr), .tx_en(w_tx_en), .sw_rst(w_sw_rst), .scram_enb(w_scram_enb), .crc_enb(w_crc_enb)
    );

    I2C_top_cci_csi u_i2c_cci (
        .i_clk(byte_clk), .i_rst_n(final_rst_n_byte), .i_scl(i2c_scl), .io_sda(i2c_sda),
        .i_packet_valid(w_pkt_valid), .i_end_of_packet(w_byte_pd),
        .o_word_count(w_cfg_wc), .o_virtual_channel(w_cfg_vc_id), .o_data_type(w_cfg_data_type),
        .o_lane_count(w_cfg_active_lanes_i2c), .o_line_number(w_i2c_line_number), .o_tx_active(w_dummy_tx_active)
    );

    wire [23:0] w_native_data;
    wire w_native_valid, w_native_ready, w_native_sof, w_native_eol;

    axi_streaming_tx u_axi_tx (
        .i_pixel_clk(pixel_clk), .i_pixel_rst_n(final_rst_n_pix), 
        .i_byte_clk(byte_clk),   .i_byte_rst_n(final_rst_n_byte),
        .i_cfg_data_type(pix_cfg_dt_sync2), // Synced
        .i_axis_tdata(tx_axis_tdata), 
        .i_axis_tvalid(tx_axis_tvalid & pix_sync_tx_en[1]), // Synced
        .o_axis_tready(tx_axis_tready), .i_axis_tuser(tx_axis_tuser), .i_axis_tlast(tx_axis_tlast),
        .o_native_data(w_native_data), .o_native_valid(w_native_valid), .i_native_ready(w_native_ready),
        .o_native_sof(w_native_sof), .o_native_eol(w_native_eol), .o_fifo_threshold_met(w_dummy_fifo_thresh), .o_fifo_stat(w_dummy_fifo_stat)
    );

    wire [7:0] w_byte_data; wire w_byte_valid, w_byte_fs, w_byte_fe, w_byte_ls;
    pixel2byte_converter u_p2b (
        .i_byte_clk(byte_clk), .i_rst_n(final_rst_n_byte), .i_cfg_data_type(w_cfg_data_type),
        .i_frame_num_lines(w_i2c_line_number), .i_native_data(w_native_data), .i_native_valid(w_native_valid),
        .o_native_ready(w_native_ready), .i_native_sof(w_native_sof), .i_native_eol(w_native_eol),
        .o_byte_data(w_byte_data), .o_byte_valid(w_byte_valid), .o_byte_frame_start(w_byte_fs),
        .o_byte_frame_end(w_byte_fe), .o_byte_line_start(w_byte_ls), .o_byte_packet_done(w_byte_pd)
    );

    wire [5:0] w_ecc_out;
    wire [25:0] w_header_data = { w_cfg_vc_id, w_cfg_data_type, w_cfg_wc[7:0], w_cfg_wc[15:8], 2'b00 };
    csi2_ecc_tx u_ecc (.i_header_data(w_header_data), .o_ecc(w_ecc_out));

    wire [7:0] w_crc_out; wire w_crc_valid;
    crc_tx u_crc (
        .clk(byte_clk), .reset_n(final_rst_n_byte), .crc_en(byte_sync_crc_enb[1]), .i_data_valid(w_byte_valid), // Synced
        .i_data_in(w_byte_data), .i_start(w_byte_ls), .i_end(w_byte_pd), .o_valid(w_crc_valid), .o_data(w_crc_out)
    );

    wire [7:0] w_pkt_data;
    csi2_packetizer u_packetizer (
        .i_byte_clk(byte_clk), .i_rst_n(final_rst_n_byte), .i_p2b_data(w_byte_data), .i_p2b_valid(w_byte_valid),
        .i_p2b_line_start(w_byte_ls), .i_p2b_packet_done(w_byte_pd), .i_p2b_frame_start(w_byte_fs),
        .i_p2b_frame_end(w_byte_fe), .i_cfg_wc(w_cfg_wc), .i_cfg_data_type(w_cfg_data_type),
        .i_cfg_vc_id(w_cfg_vc_id), .i_ecc(w_ecc_out), .i_crc_data(w_crc_out), .i_cfg_crc_en(byte_sync_crc_enb[1]), // Synced
        .o_tx_data(w_pkt_data), .o_tx_valid(w_pkt_valid), .o_frame_end(w_dummy_frame_end)
    );

    wire [1:0] w_dist_cfg_lanes = (cfg_active_lanes == 3'd4) ? 2'b11 : (cfg_active_lanes == 3'd2) ? 2'b01 : 2'b00;
    wire [7:0] w_dist_data_0, w_dist_data_1, w_dist_data_2, w_dist_data_3;
    wire w_dist_vld_0, w_dist_vld_1, w_dist_vld_2, w_dist_vld_3;
    
    lane_distributor u_dist (
        .i_clk(sys_clk), .i_rst_n(final_rst_n_sys),
        .i_pkt_data(w_pkt_data), .i_pkt_vld(w_pkt_valid),
        .i_cfg_active_lanes(w_dist_cfg_lanes),
        .o_lane0_data(w_dist_data_0), .o_lane1_data(w_dist_data_1), .o_lane2_data(w_dist_data_2), .o_lane3_data(w_dist_data_3),
        .o_lane0_vld(w_dist_vld_0),   .o_lane1_vld(w_dist_vld_1),   .o_lane2_vld(w_dist_vld_2),   .o_lane3_vld(w_dist_vld_3),
        .o_req_hs(tx_req_hs_out)
    );

    reg r_tx_active_ext; reg [3:0] tx_hang_timer;
    always @(posedge sys_clk or negedge final_rst_n_sys) begin 
        if (!final_rst_n_sys) begin r_tx_active_ext <= 0; tx_hang_timer <= 0; end 
        else begin
            if (w_pkt_valid) begin r_tx_active_ext <= 1; tx_hang_timer <= 4'd15; end 
            else if (tx_hang_timer > 0) begin tx_hang_timer <= tx_hang_timer - 1; end 
            else begin r_tx_active_ext <= 0; end
        end
    end

    // Scramblers match ModelSim functionally (w_scram_enb kept un-synced here to preserve exact testbench behavior, only fed to lint sink as before)
    mipi_scrambler #(.LANE_SEED(16'h0810)) u_scr_tx0 (.i_clk(sys_clk), .i_rst_n(final_rst_n_sys), .i_packet_active(r_tx_active_ext), .i_lane_data(w_dist_data_0), .i_lane_vld(w_dist_vld_0), .o_scrambled_data(tx_lane0_data_out), .o_lane_vld_out(tx_lane0_vld_out));
    mipi_scrambler #(.LANE_SEED(16'h0990)) u_scr_tx1 (.i_clk(sys_clk), .i_rst_n(final_rst_n_sys), .i_packet_active(r_tx_active_ext), .i_lane_data(w_dist_data_1), .i_lane_vld(w_dist_vld_1), .o_scrambled_data(tx_lane1_data_out), .o_lane_vld_out(tx_lane1_vld_out));
    mipi_scrambler #(.LANE_SEED(16'h0A51)) u_scr_tx2 (.i_clk(sys_clk), .i_rst_n(final_rst_n_sys), .i_packet_active(r_tx_active_ext), .i_lane_data(w_dist_data_2), .i_lane_vld(w_dist_vld_2), .o_scrambled_data(tx_lane2_data_out), .o_lane_vld_out(tx_lane2_vld_out));
    mipi_scrambler #(.LANE_SEED(16'h0BD0)) u_scr_tx3 (.i_clk(sys_clk), .i_rst_n(final_rst_n_sys), .i_packet_active(r_tx_active_ext), .i_lane_data(w_dist_data_3), .i_lane_vld(w_dist_vld_3), .o_scrambled_data(tx_lane3_data_out), .o_lane_vld_out(tx_lane3_vld_out));

    ppi_tx u_tx (
        .i_clk_sys(sys_clk), .i_rst_n_sys(final_rst_n_sys), .i_rst_n_tx(final_rst_n_tx), 
        .i_active_lanes(cfg_active_lanes),
        .i_lane0_data(tx_lane0_data_out), .i_lane0_vld(tx_lane0_vld_out),
        .i_lane1_data(tx_lane1_data_out), .i_lane1_vld(tx_lane1_vld_out),
        .i_lane2_data(tx_lane2_data_out), .i_lane2_vld(tx_lane2_vld_out),
        .i_lane3_data(tx_lane3_data_out), .i_lane3_vld(tx_lane3_vld_out),
        .i_req_hs(tx_req_hs_out),
        
        .i_Shutdown(1'b0), .i_TxClkEsc(1'b0), .o_TxUlpmClk(w_dummy_ulpm_clk), .o_TxRequestEsc(w_dummy_req_esc), .o_TxUlpmEsc(w_dummy_ulpm_esc),
        .o_TxClkRequestHS(ppi_tx_ClkRequestHS), .i_TxClkReadyHS(ppi_tx_ClkReadyHS), .i_TxByteClkHS(ppi_tx_ByteClkHS),
        .o_TxRequestHS(ppi_tx_RequestHS), .i_TxReadyHS(ppi_tx_ReadyHS),
        .o_lane0_data_hs(ppi_tx_DataHS_0), .o_lane0_valid_hs(ppi_tx_ValidHS_0),
        .o_lane1_data_hs(ppi_tx_DataHS_1), .o_lane1_valid_hs(ppi_tx_ValidHS_1),
        .o_lane2_data_hs(ppi_tx_DataHS_2), .o_lane2_valid_hs(ppi_tx_ValidHS_2),
        .o_lane3_data_hs(ppi_tx_DataHS_3), .o_lane3_valid_hs(ppi_tx_ValidHS_3)
    );

    // =========================================================================
    // 6. Lint Sink
    // =========================================================================
    wire w_lint_sink = &{
        1'b0, 
        cfg_frame_lines,
        w_dummy_pslverr, w_dummy_tx_active, w_dummy_fifo_thresh, w_dummy_fifo_stat,
        w_dummy_frame_end, w_dummy_ulpm_clk, w_dummy_req_esc, w_dummy_ulpm_esc,
        w_crc_valid, w_scram_enb, w_cfg_active_lanes_i2c
    };

endmodule
