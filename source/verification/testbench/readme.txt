// =============================================================================
// AVAILABLE TEST MODES
// -----------------------------------------------------------------------------
//  Mode │ Name                        │ Description
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   0   │ FULL_REGRESSION             │ All DTs × NUM_FRAMES × lane sweep
//       │                             │ (CRC/SCRAM toggled) + CRC injection +
//       │                             │ ECC injection + RAW10 sanity frame
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   1   │ RAW8_DT_SWEEP               │ DT=RAW8  (0x2A, 8 bpp)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   2   │ YUV422_DT_SWEEP             │ DT=YUV422 (0x1E, 16 bpp, 2 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   3   │ RGB565_DT_SWEEP             │ DT=RGB565 (0x22, 16 bpp, 2 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   4   │ RGB888_DT_SWEEP             │ DT=RGB888 (0x24, 24 bpp, 3 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   5   │ RAW10_DT_SWEEP              │ DT=RAW10  (0x2B, 10 bpp, 1.25 B/pixel)
//       │                             │ NUM_FRAMES frames, 4→2→1 lanes,
//       │                             │ CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   6   │ CRC_INJECT_ONLY             │ CRC 1-bit / 2-bit / 3-bit injection
//       │                             │ DT=RAW8, 4 lanes
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   7   │ ECC_INJECT_ONLY             │ ECC single-bit (SEC) + double-bit (DED)
//       │                             │ injection — DT=RAW8, 4 lanes
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   8   │ MULTI_DT_SMOKE              │ 1 frame per DT (RAW8, YUV422, RGB565,
//       │                             │ RGB888, RAW10), 4 lanes, CRC=1, SCRAM=0
// ──────┼─────────────────────────────┼─────────────────────────────────────────
//   9   │ SCRAMBLER_CRC_TOGGLE        │ All 4 {CRC,SCRAM} combos for every DT
//       │                             │ (RAW8, YUV422, RGB565, RGB888, RAW10)
//       │                             │ Fixed at 4 lanes throughout
// =============================================================================
// HOW TO SELECT A MODE
//   Change the parameter below:
//       parameter int TEST_MODE = 0;   // ← edit this number
//   Or override it from the simulator command line, e.g.:
//       vlog  tb_csi2_loopback_wrapper.sv  +define+TEST_MODE=3
//       vsim  tb_csi2_loopback_wrapper -gTEST_MODE=3
// =============================================================================