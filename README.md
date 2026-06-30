# 📸 MIPI CSI-2 Controller IP - ASIC Implementation

<p align="center">
  <img width="2309" height="840" alt="CSI2" src="https://github.com/user-attachments/assets/0a7d7d0e-315c-4c32-b29a-a4f8e13d3b94" />
</p>

## Overview
This repository contains the complete front-to-back design and implementation of a **MIPI CSI-2 Controller IP**. The project covers the full ASIC design flow from RTL development and rigorous UVM-based verification to physical implementation (RTL-to-GDSII). 

This project was developed as our Bachelor's Graduation Project at **Zewail City of Science and Technology** and was officially **sponsored and mentored by Si-Vision**.

## Key Technical Features
* **RTL & Architecture:** Synthesizable Verilog implementation of TX/RX protocol layers, featuring dynamic lane management and on-the-fly error handling (ECC/CRC).
* **Clock Domain Crossing (CDC):** Robust asynchronous FIFO integrations safely bridging Pixel, Byte, PHY, and APB domains without metastability or data loss.
* **Low Power Optimization:** Advanced architectural implementations including Clock Gating to minimize dynamic power consumption.
* **Functional Verification:** Comprehensive SystemVerilog and UVM environment ensuring end-to-end data integrity across diverse pixel formats.
* **Design For Testability (DFT):** Scan chain insertion and ATPG achieving high test coverage with zero DRC violations, ensuring production-ready testability.
* **Physical Implementation:** Complete RTL-to-GDSII flow closing timing, power, and area (PPA) with zero physical verification violations.

