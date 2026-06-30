`timescale 1ns / 1ps

module mipi_rx_top (
    // Clocks
    input  wire        sys_clk,
    input  wire        pclk,
    input  wire        pixel_clk,
    input  wire        byte_clk,

    // Resets
    input  wire        sys_rst_n,
    input  wire        preset_n,
    input  wire        pixel_rst_n,
    input  wire        byte_rst_n,

    // Configuration
    input  wire [2:0]  cfg_active_lanes,
    input  wire [5:0]  cfg_rx_data_type,

    // APB Interface
    input  wire        rx_apb_psel,
    input  wire        rx_apb_penable,
    input  wire        rx_apb_pwrite,
    input  wire [31:0] rx_apb_paddr,
    input  wire [31:0] rx_apb_pwdata,
    output wire [31:0] rx_apb_prdata,
    output wire        rx_apb_pready,

    // I2C Interface
    input  wire        i2c_scl,
    inout  wire        i2c_sda,

    // PPI RX Interface
    input  wire        ppi_rx_ByteClkHS,
    input  wire [7:0]  ppi_rx_DataHS_0,
    input  wire [7:0]  ppi_rx_DataHS_1,
    input  wire [7:0]  ppi_rx_DataHS_2,
    input  wire [7:0]  ppi_rx_DataHS_3,
    input  wire        ppi_rx_ValidHS_0,
    input  wire        ppi_rx_ValidHS_1,
    input  wire        ppi_rx_ValidHS_2,
    input  wire        ppi_rx_ValidHS_3,
    input  wire        ppi_rx_ActiveHS_0,
    input  wire        ppi_rx_ActiveHS_1,
    input  wire        ppi_rx_ActiveHS_2,
    input  wire        ppi_rx_ActiveHS_3,
    input  wire        ppi_rx_SyncHS_0,
    input  wire        ppi_rx_SyncHS_1,
    input  wire        ppi_rx_SyncHS_2,
    input  wire        ppi_rx_SyncHS_3,

    // AXI-Stream RX Interface
    output wire [31:0] rx_axis_tdata,
    output wire [3:0]  rx_axis_tkeep,
    output wire        rx_axis_tlast,
    output wire        rx_axis_tuser,
    output wire        rx_axis_tvalid,
    input  wire        rx_axis_tready,

    // Status Outputs
    output wire        rx_crc_ok,
    output wire        rx_crc_done,
    output wire        rx_ecc_single,
    output wire        rx_ecc_double
);

    // =========================================================================
    // 0. INTERNAL WIRES DECLARATION
    // =========================================================================

    wire        w_rx_en, w_sw_rst, w_scram_enb, w_crc_enb;
    wire        w_hw_crc_err, w_hw_ecc_err, w_hw_cecc_err;
    wire        w_crc_ok_int, w_crc_done_int;
    wire        w_pay_user, w_pay_last;
    wire [5:0]  w_i2c_dt;


    // =========================================================================
    // 1. HARDWARE RESET SYNCHRONIZERS (Async Assert, Sync De-assert)
    // Description : Prevents recovery metastability by ensuring resets are
    //               de-asserted synchronously to their respective clock domains.
    // Note        : Separate reset ports are maintained for ModelSim TB compatibility.
    // =========================================================================

    // --- APB / PCLK domain ---
    wire        w_presetn_sync;
    reg  [1:0]  sync_regs_apb;

    always @(posedge pclk or negedge preset_n) begin
        if (!preset_n) sync_regs_apb <= 2'b00;
        else           sync_regs_apb <= {sync_regs_apb[0], 1'b1};
    end

    assign w_presetn_sync = sync_regs_apb[1];

    // --- Pixel clock domain ---
    wire        w_rst_n_pix;
    reg  [1:0]  sync_regs_pix;

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) sync_regs_pix <= 2'b00;
        else              sync_regs_pix <= {sync_regs_pix[0], 1'b1};
    end

    assign w_rst_n_pix = sync_regs_pix[1];

    // --- System clock domain ---
    wire        w_rst_n_sys;
    reg  [1:0]  sync_regs_sys;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) sync_regs_sys <= 2'b00;
        else            sync_regs_sys <= {sync_regs_sys[0], 1'b1};
    end

    assign w_rst_n_sys = sync_regs_sys[1];

    // --- Byte clock domain ---
    wire        w_rst_n_byte;
    reg  [1:0]  sync_regs_byte;

    always @(posedge byte_clk or negedge byte_rst_n) begin
        if (!byte_rst_n) sync_regs_byte <= 2'b00;
        else             sync_regs_byte <= {sync_regs_byte[0], 1'b1};
    end

    assign w_rst_n_byte = sync_regs_byte[1];

    // --- PPI RX byte clock domain ---
    wire        w_rst_n_rx;
    reg  [1:0]  sync_regs_rx;

    always @(posedge ppi_rx_ByteClkHS or negedge sys_rst_n) begin
        if (!sys_rst_n) sync_regs_rx <= 2'b00;
        else            sync_regs_rx <= {sync_regs_rx[0], 1'b1};
    end

    assign w_rst_n_rx = sync_regs_rx[1];


    // =========================================================================
    // 2. SOFTWARE RESET INJECTION (Safe De-assertion)
    // =========================================================================

    reg [1:0] sync_sw_rst_pix;
    reg [1:0] sync_sw_rst_byte;

    always @(posedge pixel_clk or negedge w_rst_n_pix) begin
        if (!w_rst_n_pix) sync_sw_rst_pix <= 2'b00;
        else              sync_sw_rst_pix <= {sync_sw_rst_pix[0], w_sw_rst};
    end

    always @(posedge byte_clk or negedge w_rst_n_byte) begin
        if (!w_rst_n_byte) sync_sw_rst_byte <= 2'b00;
        else               sync_sw_rst_byte <= {sync_sw_rst_byte[0], w_sw_rst};
    end

    wire final_rst_n_pix  = w_rst_n_pix  & ~sync_sw_rst_pix[1];
    wire final_rst_n_byte = w_rst_n_byte & ~sync_sw_rst_byte[1];


    // =========================================================================
    // 3. CONTROL SIGNAL SYNCHRONIZERS (CDC Fixes)
    // =========================================================================

    // Sync rx_en -> byte_clk domain
    reg [1:0] byte_sync_rx_en;

    always @(posedge byte_clk or negedge final_rst_n_byte) begin
        if (!final_rst_n_byte) byte_sync_rx_en <= 2'b00;
        else                   byte_sync_rx_en <= {byte_sync_rx_en[0], w_rx_en};
    end

    // Sync crc_enb -> byte_clk domain
    reg [1:0] byte_sync_crc_enb;

    always @(posedge byte_clk or negedge final_rst_n_byte) begin
        if (!final_rst_n_byte) byte_sync_crc_enb <= 2'b00;
        else                   byte_sync_crc_enb <= {byte_sync_crc_enb[0], w_crc_enb};
    end

    // Sync crc_done -> sys_clk domain
    reg [1:0] sync_crc_done;

    always @(posedge sys_clk or negedge w_rst_n_sys) begin
        if (!w_rst_n_sys) sync_crc_done <= 2'b00;
        else              sync_crc_done <= {sync_crc_done[0], w_crc_done_int};
    end

    // Sync crc_ok -> sys_clk domain
    reg [1:0] sync_crc_ok;

    always @(posedge sys_clk or negedge w_rst_n_sys) begin
        if (!w_rst_n_sys) sync_crc_ok <= 2'b00;
        else              sync_crc_ok <= {sync_crc_ok[0], w_crc_ok_int};
    end

    // Sync ecc flags -> sys_clk domain
    reg [1:0] sync_ecc_double;
    reg [1:0] sync_ecc_single;

    always @(posedge sys_clk or negedge w_rst_n_sys) begin
        if (!w_rst_n_sys) begin
            sync_ecc_double <= 2'b00;
            sync_ecc_single <= 2'b00;
        end else begin
            sync_ecc_double <= {sync_ecc_double[0], rx_ecc_double};
            sync_ecc_single <= {sync_ecc_single[0], rx_ecc_single};
        end
    end


    // =========================================================================
    // 4. STATUS OUTPUT ASSIGNMENTS
    // =========================================================================

    assign rx_crc_ok    = w_crc_ok_int;
    assign rx_crc_done  = w_crc_done_int;
    assign w_hw_ecc_err  = rx_ecc_double;
    assign w_hw_cecc_err = rx_ecc_single;
    assign w_hw_crc_err  = w_crc_done_int & ~w_crc_ok_int;


    // =========================================================================
    // 5. STICKY ERROR LATCHES & READBACK SYNC
    // =========================================================================

    // Sticky error latches (sys_clk domain)
    reg r_mac_crc_sticky;
    reg r_mac_ecc_sticky;
    reg r_mac_cecc_sticky;

    always @(posedge sys_clk or negedge w_rst_n_sys) begin
        if (!w_rst_n_sys) begin
            r_mac_crc_sticky  <= 1'b0;
            r_mac_ecc_sticky  <= 1'b0;
            r_mac_cecc_sticky <= 1'b0;
        end else begin
            if (sync_crc_done[1] & ~sync_crc_ok[1]) r_mac_crc_sticky  <= 1'b1;
            if (sync_ecc_double[1])                  r_mac_ecc_sticky  <= 1'b1;
            if (sync_ecc_single[1])                  r_mac_cecc_sticky <= 1'b1;
        end
    end

    // 2-stage sync: sys_clk sticky flags -> PCLK domain (for APB readback)
    reg [1:0] sync_crc_level;
    reg [1:0] sync_ecc_level;
    reg [1:0] sync_cecc_level;

    always @(posedge pclk or negedge w_presetn_sync) begin
        if (!w_presetn_sync) begin
            sync_crc_level  <= 2'b00;
            sync_ecc_level  <= 2'b00;
            sync_cecc_level <= 2'b00;
        end else begin
            sync_crc_level  <= {sync_crc_level[0],  r_mac_crc_sticky};
            sync_ecc_level  <= {sync_ecc_level[0],  r_mac_ecc_sticky};
            sync_cecc_level <= {sync_cecc_level[0], r_mac_cecc_sticky};
        end
    end


    // =========================================================================
    // 6. MODULE INSTANTIATIONS
    // =========================================================================

    // --- APB Register File ---
    apb_csi2_rx_regfile u_regfile (
        .PCLK        (pclk),
        .PRESETn     (w_presetn_sync),
        .PSEL        (rx_apb_psel),
        .PENABLE     (rx_apb_penable),
        .PWRITE      (rx_apb_pwrite),
        .PSTRB       (4'hF),
        .PADDR       (rx_apb_paddr),
        .PWDATA      (rx_apb_pwdata),
        .PRDATA      (rx_apb_prdata),
        .PREADY      (rx_apb_pready),
        .PSLVERR     (),
        .hw_crc_err  (sync_crc_level[1]),
        .hw_ecc_err  (sync_ecc_level[1]),
        .hw_cecc_err (sync_cecc_level[1]),
        .sw_rst      (w_sw_rst),
        .rx_en       (w_rx_en),
        .rx_crc_enb  (w_crc_enb),
        .rx_scram_enb(w_scram_enb)
    );

    // --- I2C CCI ---
    I2C_top_cci_csi_rx u_i2c_cci_rx (
        .i_clk           (byte_clk),
        .i_rst_n         (final_rst_n_byte),
        .i_SCL           (i2c_scl),
        .io_sda          (i2c_sda),
        .i_packet_start  (w_pay_user),
        .i_packet_end    (w_pay_last),
        .o_virtual_channel(),
        .o_data_type     (w_i2c_dt),
        .o_lane_count    (),
        .o_line_number   (),
        .o_word_count    (),
        .o_rx_active     ()
    );

    // --- PPI RX ---
    wire        w_pull_data;
    wire [7:0]  w_rx_lane0_data, w_rx_lane1_data, w_rx_lane2_data, w_rx_lane3_data;
    wire        w_rx_lane0_valid, w_rx_lane1_valid, w_rx_lane2_valid, w_rx_lane3_valid;
    wire        w_packet_active_rx, w_rx_ready;

    ppi_rx u_rx (
        .i_clk_sys       (sys_clk),
        .i_rst_n_sys     (w_rst_n_sys),
        .i_rst_n_rx      (w_rst_n_rx),
        .i_RxByteClkHS   (ppi_rx_ByteClkHS),

        .i_RxDataHS_0    (ppi_rx_DataHS_0),
        .i_RxValidHS_0   (ppi_rx_ValidHS_0),
        .i_RxActiveHS_0  (ppi_rx_ActiveHS_0),
        .i_RxSyncHS_0    (ppi_rx_SyncHS_0),

        .i_RxDataHS_1    (ppi_rx_DataHS_1),
        .i_RxValidHS_1   (ppi_rx_ValidHS_1),
        .i_RxActiveHS_1  (ppi_rx_ActiveHS_1),
        .i_RxSyncHS_1    (ppi_rx_SyncHS_1),

        .i_RxDataHS_2    (ppi_rx_DataHS_2),
        .i_RxValidHS_2   (ppi_rx_ValidHS_2),
        .i_RxActiveHS_2  (ppi_rx_ActiveHS_2),
        .i_RxSyncHS_2    (ppi_rx_SyncHS_2),

        .i_RxDataHS_3    (ppi_rx_DataHS_3),
        .i_RxValidHS_3   (ppi_rx_ValidHS_3),
        .i_RxActiveHS_3  (ppi_rx_ActiveHS_3),
        .i_RxSyncHS_3    (ppi_rx_SyncHS_3),

        .i_lane0_rd_en   (w_pull_data),
        .i_lane1_rd_en   (w_pull_data),
        .i_lane2_rd_en   (w_pull_data),
        .i_lane3_rd_en   (w_pull_data),

        .o_lane0_data    (w_rx_lane0_data),
        .o_lane1_data    (w_rx_lane1_data),
        .o_lane2_data    (w_rx_lane2_data),
        .o_lane3_data    (w_rx_lane3_data),

        .o_lane0_valid   (w_rx_lane0_valid),
        .o_lane1_valid   (w_rx_lane1_valid),
        .o_lane2_valid   (w_rx_lane2_valid),
        .o_lane3_valid   (w_rx_lane3_valid),

        .o_packet_active (w_packet_active_rx),
        .o_rx_ready      (w_rx_ready),

        .i_Shutdown      (1'b0),
        .i_Stopstate_0   (1'b0),
        .i_Stopstate_1   (1'b0),
        .i_Stopstate_2   (1'b0),
        .i_Stopstate_3   (1'b0),
        .i_RxUlpmEsc_0   (1'b0),
        .i_RxUlpmEsc_1   (1'b0),
        .i_RxUlpmEsc_2   (1'b0),
        .i_RxUlpmEsc_3   (1'b0),
        .i_ErrSotHS_0    (1'b0),
        .i_ErrSotHS_1    (1'b0),
        .i_ErrSotHS_2    (1'b0),
        .i_ErrSotHS_3    (1'b0),
        .i_ErrSotSyncHS_0(1'b0),
        .i_ErrSotSyncHS_1(1'b0),
        .i_ErrSotSyncHS_2(1'b0),
        .i_ErrSotSyncHS_3(1'b0),
        .i_ErrControl_0  (1'b0),
        .i_ErrControl_1  (1'b0),
        .i_ErrControl_2  (1'b0),
        .i_ErrControl_3  (1'b0),
        .i_ErrEsc_0      (1'b0),
        .i_ErrEsc_1      (1'b0),
        .i_ErrEsc_2      (1'b0),
        .i_ErrEsc_3      (1'b0),
        .o_rx_error_flag ()
    );

    // --- MIPI Descramblers (one per lane) ---
    wire [7:0] w_desc_data_0, w_desc_data_1, w_desc_data_2, w_desc_data_3;
    wire       w_desc_vld_0,  w_desc_vld_1,  w_desc_vld_2,  w_desc_vld_3;

    mipi_descrambler #(.LANE_SEED(16'h0810)) u_desc0 (
        .i_clk             (sys_clk),
        .i_rst_n           (w_rst_n_sys),
        .i_packet_active   (w_packet_active_rx),
        .i_scrambled_data  (w_rx_lane0_data),
        .i_lane_vld        (w_rx_lane0_valid),
        .o_descrambled_data(w_desc_data_0),
        .o_lane_vld_out    (w_desc_vld_0)
    );

    mipi_descrambler #(.LANE_SEED(16'h0990)) u_desc1 (
        .i_clk             (sys_clk),
        .i_rst_n           (w_rst_n_sys),
        .i_packet_active   (w_packet_active_rx),
        .i_scrambled_data  (w_rx_lane1_data),
        .i_lane_vld        (w_rx_lane1_valid),
        .o_descrambled_data(w_desc_data_1),
        .o_lane_vld_out    (w_desc_vld_1)
    );

    mipi_descrambler #(.LANE_SEED(16'h0A51)) u_desc2 (
        .i_clk             (sys_clk),
        .i_rst_n           (w_rst_n_sys),
        .i_packet_active   (w_packet_active_rx),
        .i_scrambled_data  (w_rx_lane2_data),
        .i_lane_vld        (w_rx_lane2_valid),
        .o_descrambled_data(w_desc_data_2),
        .o_lane_vld_out    (w_desc_vld_2)
    );

    mipi_descrambler #(.LANE_SEED(16'h0BD0)) u_desc3 (
        .i_clk             (sys_clk),
        .i_rst_n           (w_rst_n_sys),
        .i_packet_active   (w_packet_active_rx),
        .i_scrambled_data  (w_rx_lane3_data),
        .i_lane_vld        (w_rx_lane3_valid),
        .o_descrambled_data(w_desc_data_3),
        .o_lane_vld_out    (w_desc_vld_3)
    );

    // --- Lane Merger ---
    wire [7:0] w_merged_data;
    wire       w_merged_valid;

    lane_merger u_merger (
        .i_clk          (sys_clk),
        .i_rst_n        (w_rst_n_sys),
        .i_active_lanes (cfg_active_lanes),
        .i_packet_active(w_packet_active_rx),
        .i_rx_ready     (w_rx_ready),
        .i_lane0_data   (w_desc_data_0),
        .i_lane1_data   (w_desc_data_1),
        .i_lane2_data   (w_desc_data_2),
        .i_lane3_data   (w_desc_data_3),
        .i_lane0_vld    (w_desc_vld_0),
        .i_lane1_vld    (w_desc_vld_1),
        .i_lane2_vld    (w_desc_vld_2),
        .i_lane3_vld    (w_desc_vld_3),
        .o_pull_data    (w_pull_data),
        .o_merged_data  (w_merged_data),
        .o_merged_valid (w_merged_valid)
    );

    // --- RX Depacketizer ---
    wire [7:0]  w_pay_data, w_crc_data;
    wire        w_pay_valid;
    wire [31:0] w_ecc_hdr_data;
    wire        w_crc_valid, w_crc_start, w_crc_end;

    rx_depacketizer u_depacketizer (
        .i_clk        (byte_clk),
        .i_rst_n      (final_rst_n_byte),
        .i_cfg_crc_en (byte_sync_crc_enb[1]),
        .i_rx_data    (w_merged_data),
        .i_rx_valid   (w_merged_valid),
        .o_pay_data   (w_pay_data),
        .o_pay_valid  (w_pay_valid),
        .o_pay_last   (w_pay_last),
        .o_pay_user   (w_pay_user),
        .o_ecc_hdr_data(w_ecc_hdr_data),
        .o_crc_data   (w_crc_data),
        .o_crc_valid  (w_crc_valid),
        .o_crc_start  (w_crc_start),
        .o_crc_end    (w_crc_end)
    );

    // --- ECC RX ---
    reg r_hdr_valid_d;

    always @(posedge byte_clk or negedge final_rst_n_byte) begin
        if (!final_rst_n_byte) r_hdr_valid_d <= 1'b0;
        else                   r_hdr_valid_d <= w_pay_user & w_pay_valid;
    end

    csi2_ecc_rx u_ecc_rx (
        .i_clk             (byte_clk),
        .i_rst             (~final_rst_n_byte),
        .i_header_valid    (r_hdr_valid_d),
        .i_received_header (w_ecc_hdr_data),
        .o_single_bit_error(rx_ecc_single),
        .o_double_bit_error(rx_ecc_double),
        .o_corrected_header(),
        .o_header_valid    (),
        .o_ecc_rx          (),
        .o_ecc_calc        (),
        .o_syndrome        (),
        .o_error_index     ()
    );

    // --- CRC RX ---
    crc_rx u_crc_rx (
        .clk          (byte_clk),
        .reset_n      (final_rst_n_byte),
        .crc_en       (byte_sync_crc_enb[1]),
        .i_data_valid (w_crc_valid),
        .i_data_in    (w_crc_data),
        .i_start      (w_crc_start),
        .i_end        (w_crc_end),
        .o_crc_ok     (w_crc_ok_int),
        .o_crc_done   (w_crc_done_int)
    );

    // --- CSI-2 RX Unpacker ---
    wire [23:0] w_native_data;
    wire        w_native_valid, w_native_sof, w_native_eol;

    csi2_rx_unpacker #(.MAX_PIXEL_WIDTH(24)) u_unpacker (
        .i_byte_clk       (byte_clk),
        .i_rst_n          (final_rst_n_byte),
        .i_cfg_data_type  (w_i2c_dt),
        .i_rx_data        (w_pay_data),
        .i_rx_valid       (w_pay_valid),
        .i_rx_packet_done (w_pay_last),
        .i_rx_frame_start (w_pay_user),
        .o_native_data    (w_native_data),
        .o_native_valid   (w_native_valid),
        .o_native_sof     (w_native_sof),
        .o_native_eol     (w_native_eol)
    );

    // --- Async CDC FIFO ---
    wire [25:0] w_fifo_rdata;
    wire        w_fifo_empty, w_bridge_pix_ready;

    async_fifo_behavioral #(.DEPTH(2048), .WIDTH(26)) u_cdc_fifo (
        .wclk   (byte_clk),
        .wrst_n (final_rst_n_byte),
        .winc   (w_native_valid),
        .wdata  ({w_native_eol, w_native_sof, w_native_data}),
        .rclk   (pixel_clk),
        .rrst_n (final_rst_n_pix),
        .rinc   (w_bridge_pix_ready & ~w_fifo_empty),
        .rdata  (w_fifo_rdata),
        .rempty (w_fifo_empty),
        .wfull  (),
        .rd_count()
    );

    // --- AXI-Stream Bridge ---
    axi_stream_bridge #(.P_PIX_WIDTH(24), .P_AXI_WIDTH(32)) u_axi_bridge (
        .i_aclk       (pixel_clk),
        .i_aresetn    (final_rst_n_pix),
        .i_pix_data   (w_fifo_rdata[23:0]),
        .i_pix_last   (w_fifo_rdata[25]),
        .i_pix_user   (w_fifo_rdata[24]),
        .i_pix_valid  (~w_fifo_empty),
        .o_pix_ready  (w_bridge_pix_ready),
        .m_axis_tdata (rx_axis_tdata),
        .m_axis_tkeep (rx_axis_tkeep),
        .m_axis_tlast (rx_axis_tlast),
        .m_axis_tuser (rx_axis_tuser),
        .m_axis_tvalid(rx_axis_tvalid),
        .m_axis_tready(rx_axis_tready)
    );

endmodule  
