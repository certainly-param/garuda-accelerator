# Garuda: RISC-V ML Accelerator

> **7.5-9× lower tail latency for batch-1 attention microkernels** — A CVXIF coprocessor that extends RISC-V with custom INT8 MAC instructions, optimized for transformer inference on on-SoC deployments.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-In%20Development-yellow.svg)]()
[![CI](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml/badge.svg)](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml)
[![GitHub stars](https://img.shields.io/github/stars/certainly-param/garuda-accelerator.svg?style=social&label=Star)](https://github.com/certainly-param/garuda-accelerator)
[![GitHub watchers](https://img.shields.io/github/watchers/certainly-param/garuda-accelerator.svg?style=social&label=Watch)](https://github.com/certainly-param/garuda-accelerator)
[![RISC-V](https://img.shields.io/badge/RISC--V-CVXIF-green.svg)](https://github.com/openhwgroup/core-v-xif)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-2012-orange.svg)]()
[![Testbenches](https://img.shields.io/badge/Testbenches-5%20PASSING-brightgreen.svg)]()
[![Synthesis](https://img.shields.io/badge/Synthesis-Yosys%20CI-yellow.svg)]()

## Overview

**Garuda** is a CVXIF coprocessor that extends RISC-V with custom INT8 multiply-accumulate (MAC) instructions, optimized for **batch-1 tail latency** (p99). Ideal for real-time transformer inference, voice assistants, and local LLM attention workloads.

**Key Achievement**: 7.5-9× latency reduction vs. modeled baseline for attention microkernels (p99: 307→34 cycles).

### Quick Start

```bash
git clone https://github.com/certainly-param/garuda-accelerator.git
cd garuda-accelerator
git submodule update --init --recursive

# Run simulation
iverilog -g2012 -o sim_test.vvp garuda/tb/tb_attention_microkernel_latency.sv garuda/rtl/attention_microkernel_engine.sv
vvp sim_test.vvp
```

---

## Performance

### Latency (Attention Microkernel)

**Workload**: Q·K dot product (K=128 INT8 elements)

| Metric | Baseline | Garuda | Improvement |
|---|---:|---:|---:|
| p50 latency | 256 cycles | 34 cycles | **7.5×** |
| p95 latency | 291 cycles | 34 cycles | **8.6×** |
| p99 latency | 307 cycles | 34 cycles | **9.0×** |

*Measured via `tb_attention_microkernel_latency.sv` (1000 trials). Baseline models CPU-style SIMD_DOT loop with dispatch jitter.*

### Instruction Performance

| Operation | Standard RISC-V | With Garuda | Speedup |
|---|---:|---:|---:|
| Single MAC | 2 instructions | 1 instruction | 2× |
| 4-elem dot product | 16 instructions | 1 instruction | 16× |
| MAC latency | 5-8 cycles | 3-4 cycles | 1.6-2× |

---

## Features

### Custom Instructions

| Instruction | Opcode | Description | Latency |
|------------|--------|-------------|---------|
| `MAC8` | 0x0001 | INT8 MAC, 8-bit accumulator | 3-4 cycles |
| `MAC8.ACC` | 0x0002 | INT8 MAC, 32-bit accumulator | 3-4 cycles |
| `MUL8` | 0x0003 | INT8 multiply | 2-3 cycles |
| `CLIP8` | 0x0004 | Saturate to INT8 range | 1 cycle |
| `SIMD_DOT` | 0x0005 | 4-element SIMD dot product | 3-4 cycles |
| `ATT_DOT_SETUP` | 0x0008 | Configure attention microkernel | 1 cycle |
| `ATT_DOT_RUN` | 0x0009 | Stage & execute dot product | Variable |
| `ATT_DOT_RUN_SCALE` | 0x000A | Run with scaling | Variable |
| `ATT_DOT_RUN_CLIP` | 0x000B | Run with scaling + clipping | Variable |

All instructions use RISC-V `custom-3` opcode (0x7B).

### Architecture

- **CVXIF Interface**: Standard coprocessor protocol (no CPU changes required)
- **Attention Microkernel Engine**: Internal deterministic loop execution, eliminates CPU dispatch overhead
- **Multi-Issue Support**: Register rename table enables 4-wide instruction issue
- **INT8 Quantization**: 4× memory reduction vs. FP32, lower power consumption

**Key Modules:**
- `int8_mac_unit.sv`: Core MAC execution unit
- `attention_microkernel_engine.sv`: Latency-optimized attention engine
- `int8_mac_decoder.sv`: CVXIF instruction decoder
- `register_rename_table.sv`: Multi-issue rename infrastructure

---

## Getting Started

### Prerequisites

- **Simulator**: Icarus Verilog, Verilator, QuestaSim, or VCS
- **RISC-V Toolchain**: For software development
- **Python 3.7+**: For Cocotb verification tests

### Run Simulations

**Icarus Verilog:**
```bash
iverilog -g2012 -o sim_rr.vvp garuda/tb/tb_register_rename_table.sv garuda/rtl/register_rename_table.sv
vvp sim_rr.vvp
```

**Verilator (all testbenches):**
```bash
bash ci/run_verilator_sims.sh
```

**Cocotb tests:**
```bash
cd garuda/dv && make
```

### CVA6 Integration

The `integration/` directory contains a full system testbench integrating Garuda with the CVA6 RISC-V CPU:

```bash
cd integration
make SIM=verilator compile-debug
make SIM=verilator run
```

**Supported Simulators:**
- Verilator (recommended)
- QuestaSim
- VCS
- Icarus Verilog

**Files:**
- `system_top.sv`: Top-level module wiring CVA6 + Garuda + Memory
- `tb_system_top.sv`: System-level testbench
- `memory_model.sv`: AXI memory model
- `Makefile.commercial`: Multi-simulator build automation
- `extract_cva6_files.py`: CVA6 RTL file extraction script

**Architecture:**
```
┌─────────────────────────────────────────────┐
│         tb_system_top.sv                     │
│         (Testbench)                          │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│           system_top.sv                      │
│                                             │
│  ┌──────────┐         ┌──────────┐         │
│  │   CVA6   │◄────CVXIF────►│ Garuda │     │
│  │   CPU    │         │Coprocessor│         │
│  └────┬─────┘         └──────────┘         │
│       │                                     │
│       │ NoC (AXI)                           │
│       │                                     │
│       ▼                                     │
│  ┌──────────┐                              │
│  │  Memory  │                              │
│  │  Model   │                              │
│  └──────────┘                              │
└─────────────────────────────────────────────┘
```

**Note:** CVA6 is included as a git submodule. Run `git submodule update --init --recursive` before building.

---

## Usage Example

**SIMD Dot Product (C with inline assembly):**
```c
static inline int32_t simd_dot(int32_t acc, uint32_t a_packed, uint32_t b_packed) {
    int32_t result;
    asm volatile (
        "simd_dot %0, %1, %2"
        : "=r" (result)
        : "r" (a_packed), "r" (b_packed), "0" (acc)
    );
    return result;
}
```

**Attention Microkernel:**
```c
// Configure engine
att_dot_setup(k_elements, shift, scale);  // Q8.8 format

// Stage operands and execute (one instruction per word pair)
for (i = 0; i < k_elements / 4; i++) {
    uint32_t q_word = *(uint32_t*)&q[i * 4];
    uint32_t k_word = *(uint32_t*)&k[i * 4];
    result = att_dot_run_scale(q_word, k_word);
}
```

---

## Verification

**Testbenches (5 passing):**
- `tb_int8_mac_unit.sv`: Basic MAC operations
- `tb_attention_microkernel_engine.sv`: Attention microkernel
- `tb_attention_microkernel_latency.sv`: Latency measurement (1000 trials)
- `tb_register_rename_table.sv`: Multi-issue rename logic
- `tb_attention_microkernel_cvxif.sv`: CVXIF integration test

**CI**: Automated Icarus Verilog and Verilator tests on every push/PR. [View CI results](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml)

---

## Repository Structure

```
garuda-accelerator/
├── garuda/
│   ├── rtl/          # RTL source files
│   ├── tb/           # Testbenches
│   ├── dv/           # Cocotb verification
│   └── synth/        # Synthesis scripts
├── integration/      # CVA6 integration testbench
│   ├── system_top.sv      # Top-level system (CVA6 + Garuda + Memory)
│   ├── tb_system_top.sv   # System testbench
│   ├── memory_model.sv    # AXI memory model
│   ├── Makefile.commercial # Multi-simulator build system
│   └── extract_cva6_files.py # CVA6 file extraction
├── ci/               # CI helper scripts
└── .github/workflows/ # CI workflows
```

---

## Technical Specifications

- **Interface**: CVXIF (Core-V eXtension Interface)
- **Data Width**: 32-bit (XLEN=32)
- **MAC Latency**: 3-4 cycles
- **SIMD_DOT Latency**: 3-4 cycles (4 INT8 MACs)
- **Attention Dot Latency**: K/4 + post-op cycles (deterministic)
- **Max Dot Product Length**: 256 INT8 elements (64 words)

---

## Use Cases

- **Transformer Attention**: Q·K^T dot products for attention scores (7.5-9× latency reduction)
- **Real-Time Voice Assistants**: Low-latency inference with deterministic execution
- **Local LLM Inference**: Batch-1 queries optimized for tail latency
- **Edge AI**: Low power, predictable performance for embedded systems

**Why Batch-1?** Edge devices have limited memory, power constraints, and real-time requirements. Batch-1 processing enables immediate response without waiting for batch to fill, matching event-driven embedded workloads.

---

## Implementation Status

**Completed:**
- INT8 MAC unit with all basic operations
- SIMD_DOT instruction (4× speedup)
- Attention microkernel engine
- CVXIF interface integration
- CVA6 CPU connection
- 5 passing testbenches

**Future Work:**
- FPGA/ASIC implementation and benchmarking
- Power consumption analysis
- Extended instruction set

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## References

- [CV-X-IF Specification](https://github.com/openhwgroup/core-v-xif)
- [CVA6 Documentation](https://docs.openhwgroup.org/projects/cva6-user-manual/)
- [RISC-V ISA Manual](https://riscv.org/technical/specifications/)

---

## License

- **Garuda RTL**: Apache License 2.0
- **CVA6**: Solderpad Hardware License v0.51
- **Documentation**: Creative Commons BY 4.0

---

## Star This Project

If you find Garuda useful or interesting, please consider giving it a ⭐ star on GitHub! It helps others discover the project and shows your support.

---

Made with ❤️
