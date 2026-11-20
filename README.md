# FIFO Design and Verification using SystemVerilog

Parameterized synchronous and asynchronous FIFO implementations using SystemVerilog, with self-checking testbenches and FPGA implementation analysis using Xilinx Vivado.

## Overview

This repository contains two FIFO architectures:

1. **Synchronous FIFO** – single-clock FIFO with binary read/write pointers and full/empty detection.
2. **Asynchronous FIFO** – dual-clock FIFO using Gray-code pointers and two-flop synchronizers for clock-domain crossing (CDC).

The project focuses on RTL design, functional verification, CDC architecture, and FPGA implementation analysis.

## 1. Synchronous FIFO

### Architecture

- Single-clock FIFO.
- Parameterized data width and FIFO depth.
- Binary read and write pointers with an additional wrap-around bit.
- Full and empty flag generation.
- Registered read data output.
- Protection against writes when full and reads when empty.

### Verification

A self-checking SystemVerilog testbench uses an independent queue-based reference model to check FIFO data ordering and operation behavior.

Verification scenarios include:
- Write and read operations.
- Full and empty conditions.
- Overflow and underflow blocking.
- Simultaneous read/write operations.
- Randomized stimulus.

### FPGA Implementation Results

Vivado implementation results for DATA_W = 8 and DEPTH = 8:

| Resource / Metric | Result |
|---|---:|
| CLB LUTs | 17 |
| CLB Registers | 16 |
| BRAM | 0 |
| DSP | 0 |
| WNS | +8.258 ns |
| TNS | 0 ns |
| WHS | +0.038 ns |
| THS | 0 ns |

The FIFO memory was mapped to distributed RAM resources rather than block RAM.

## 2. Asynchronous FIFO

### Architecture

- Independent write and read clock domains.
- Parameterized data width and FIFO depth.
- Binary pointers for local memory addressing.
- Gray-code pointer conversion for CDC.
- Two-flop synchronizers for pointer transfer between clock domains.
- Full detection in the write clock domain.
- Empty detection in the read clock domain.
- Registered read data output.

Gray-code pointers ensure that only one bit changes between consecutive pointer values, helping reduce CDC sampling ambiguity.

### Verification

The testbench uses independent write and read clocks and a queue-based scoreboard.

Test scenarios include:
- Independent write and read operations.
- Different clock frequencies and clock ratios.
- Write-only and read-only traffic.
- Randomized traffic.
- Full and empty conditions.
- Data ordering checks.
- Overflow and underflow blocking.

### FPGA Implementation Results

| Resource / Metric | Result |
|---|---:|
| CLB LUTs | 24 |
| CLB Registers | 40 |
| Distributed RAM LUTs | 8 |
| BRAM | 0 |
| DSP | 0 |
| WNS | +8.445 ns |
| TNS | 0 ns |
| WHS | +0.075 ns |
| THS | 0 ns |

### CDC Analysis

Vivado post-implementation CDC analysis reported:

| CDC Result | Count |
|---|---:|
| Structurally safe endpoints | 16 |
| Unsafe endpoints | 0 |
| Missing ASYNC_REG endpoints | 0 |
| Unknown CDC endpoints | 0 |

These results represent structural CDC analysis and do not constitute a guarantee that metastability can never occur.

## 3. Tools and Technologies

- SystemVerilog
- Xilinx Vivado 2024.2
- RTL simulation and self-checking testbenches
- FPGA synthesis and implementation
- Static timing analysis
- Clock-domain crossing analysis

## 4. Key Concepts Demonstrated

- Parameterized RTL design
- FIFO pointer management
- Full and empty flag generation
- Binary-to-Gray code conversion
- Clock-domain crossing
- Two-flop synchronization
- Queue-based reference modeling
- Self-checking verification
- FPGA resource utilization and timing analysis

## 5. Notes

- FIFO configurations use power-of-two depths.
- Timing results are specific to the selected FPGA target and implementation settings.
- External input/output delay constraints were not fully specified in the reported timing analysis. Board-level timing evaluation requires appropriate I/O constraints.
- CDC structural analysis does not replace functional verification or physical design review.

