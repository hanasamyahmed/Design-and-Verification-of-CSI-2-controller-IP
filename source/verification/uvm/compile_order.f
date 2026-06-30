# =============================================================================
# CSI-2 UVM Environment – Compilation File List
# =============================================================================
# Compile order: dependencies must appear BEFORE the files that import them.
# Use with ModelSim/Questa:
#   vlog -sv -work work -f compile_order.f
# Or with VCS:
#   vcs -sverilog -f compile_order.f
# =============================================================================

# ---- 1. UVM base library (simulator provides this; add path if needed) ----
# $UVM_HOME/src/uvm_pkg.sv   (un-comment and set path if not auto-included)

# ---- 2. RTL Design-Under-Test ----
# (Add your RTL files here – they must be compiled before the TB)
# mipi_tx_top.v
# mipi_rx_top.v
# mipi_system_top.v          ← top wrapper that tb_top instantiates
# dphy_behavioral.v

# ---- 3. Interfaces (no package dependencies) ----
csi_if.sv                    # csi_tx_if  +  csi_rx_if

# ---- 4. Leaf packages (no inter-package dependencies) ----
csi_seq_item.sv              # csi_seq_item_pkg
csi_config.sv                # csi_config_pkg

# ---- 5. Sequencer ----
csi_tx_sequencer.sv          # csi_tx_sequencer_pkg

# ---- 6. Driver & Monitors (depend on seq_item + config) ----
csi_tx_driver.sv             # csi_tx_driver_pkg
csi_tx_monitor.sv            # csi_tx_monitor_pkg
csi_rx_monitor.sv            # csi_rx_monitor_pkg  (defines csi_rx_status_item too)

# ---- 7. Agents (depend on sequencer + driver + monitors + config) ----
csi_tx_agent.sv              # csi_tx_agent_pkg
csi_rx_agent.sv              # csi_rx_agent_pkg

# ---- 8. Scoreboard & Coverage (depend on seq_item + rx_monitor) ----
csi_scoreboard.sv            # csi_scoreboard_pkg
csi_coverage.sv              # csi_coverage_pkg

# ---- 9. Environment (depends on agents + scoreboard + coverage) ----
csi_top_env.sv               # csi_top_env_pkg

# ---- 10. Sequences (depend on seq_item + driver) ----
csi_frame_sequence.sv        # csi_frame_sequence_pkg

# ---- 11. Test (depends on env + sequences + config) ----
csi_system_test.sv           # csi_system_test_pkg

# ---- 12. SVA module (no package deps, instantiated in tb_top) ----
csi_sva.sv

# ---- 13. TB Top (depends on everything above) ----
csi_tb_top.sv
