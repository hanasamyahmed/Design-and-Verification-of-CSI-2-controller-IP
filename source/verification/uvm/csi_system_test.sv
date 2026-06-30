// =============================================================================
// File        : csi_system_test.sv
// Date        : Jun 2026
// Author      : Hana Samy
// Description : Top-level UVM test for the CSI-2 TX->D-PHY->RX loopback.
// =============================================================================
 
package csi_system_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import csi_config_pkg::*;
    import csi_seq_item_pkg::*;
    import csi_top_env_pkg::*;
    import csi_frame_sequence_pkg::*;
 
    class csi_system_test extends uvm_test;
        `uvm_component_utils(csi_system_test)
 
        csi_top_env  env;
        csi_config   cfg;
 
        function new(string name = "csi_system_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction : new
 
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cfg = csi_config::type_id::create("cfg");
            if (!uvm_config_db #(virtual csi_tx_if)::get(this, "", "tx_vif", cfg.tx_vif))
                `uvm_fatal("build_phase", "Test: cannot get tx_vif from config_db")
            if (!uvm_config_db #(virtual csi_rx_if)::get(this, "", "rx_vif", cfg.rx_vif))
                `uvm_fatal("build_phase", "Test: cannot get rx_vif from config_db")
            uvm_config_db #(csi_config)::set(this, "*", "CSI_CFG", cfg);
            env = csi_top_env::type_id::create("env", this);
        endfunction : build_phase
 
        task run_phase(uvm_phase phase);
        csi_frame_sequence seq;
        // 1. Array of the 5 supported data types
        logic [5:0] dt_array [5] = '{6'h2A, 6'h2B, 6'h1E, 6'h22, 6'h24};
        
        phase.raise_objection(this);
        
        // 2. Loop through all 5 formats
        for (int i = 0; i < 5; i++) begin
            `uvm_info("TEST", $sformatf("Starting sequence for Data Type: 0x%02X", dt_array[i]), UVM_NONE)
            
            seq = csi_frame_sequence::type_id::create("seq");
            seq.num_pixels_per_line = cfg.num_pixels_per_line;
            seq.num_lines_per_frame = cfg.num_lines_per_frame;
            seq.num_frames          = cfg.num_frames;
            
            // 3. Inject the current data type into the sequence
            seq.cfg_data_type       = dt_array[i]; 
            
            seq.start(env.tx_input_agent.sqr);
        end
        
        phase.drop_objection(this);
    endtask
 
        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.print_topology();
        endfunction : end_of_elaboration_phase
 
    endclass : csi_system_test
 
endpackage : csi_system_test_pkg