# Garuda: RISC-V ML Accelerator

> **7.5-9× lower tail latency for batch-1 attention microkernels** — A CVXIF coprocessor that extends RISC-V with custom INT8 MAC instructions, optimized for transformer inference on on-SoC deployments.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml/badge.svg)](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml)
[![RISC-V](https://img.shields.io/badge/RISC--V-CVXIF-green.svg)](https://github.com/openhwgroup/core-v-xif)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-2012-orange.svg)]()
[![Testbenches](https://img.shields.io/badge/Testbenches-4%20PASSING-brightgreen.svg)]()
[![Synthesis](https://img.shields.io/badge/Synthesis-Yosys%20CI-yellow.svg)]()

## What is Garuda?

**Garuda** is a CVXIF coprocessor that extends RISC-V with custom INT8 multiply-accumulate (MAC) instructions for efficient neural network inference. Unlike throughput-oriented accelerators that require batching, Garuda optimizes for **batch-1 tail latency** (p99), making it ideal for real-time transformer inference, voice assistants, and local LLM attention workloads.

**Key advantage**: Achieves **7.5-9× latency reduction** vs baseline CPU-style loops (p99: 307→34 cycles) for attention dot products while maintaining competitive throughput for larger dense layers.

### Quick Start

```bash
# Clone and setup
git clone https://github.com/certainly-param/garuda-accelerator.git
cd garuda-accelerator

# Install Icarus Verilog (Ubuntu: sudo apt-get install iverilog)

# Run a simulation
iverilog -g2012 -o sim_test.vvp garuda/tb/tb_attention_microkernel_latency.sv garuda/rtl/attention_microkernel_engine.sv
vvp sim_test.vvp
```

**Ready in 3 commands.** See [Getting Started](#getting-started) for detailed setup.

---

## Why Garuda?

- **Low tail latency**: 7.5-9× faster p99 latency for batch-1 attention microkernels (307→34 cycles)
- **Standard integration**: CVXIF protocol — no CPU modifications required
- **High throughput**: SIMD_DOT instruction provides 4× speedup vs scalar operations
- **On-SoC optimized**: Designed for cache-coherent integration next to RISC-V CPU cores
- **Verified**: Continuous integration with automated testbenches and synthesis

---

## Performance & Stats

### Latency Performance (Attention Microkernel)

**Workload**: Q·K dot product (K=128 INT8 elements = 32 words × 4 INT8/word) — single-head attention score computation

| Metric | Baseline (CPU-style) | Garuda Microkernel | Improvement |
|---|---:|---:|---:|
| p50 latency | 256 cycles | 34 cycles | **7.5×** |
| p95 latency | 291 cycles | 34 cycles | **8.6×** |
| p99 latency | 307 cycles | 34 cycles | **9.0×** |

*Measured via `tb_attention_microkernel_latency.sv` (1000 trials, Icarus simulation). Baseline models CPU-style loop with dispatch jitter; microkernel uses deterministic internal loop.*

**Why this matters**: Lower tail latency (p99) is critical for real-time applications. Garuda's microkernel engine eliminates dispatch overhead by running the dot-product loop internally, achieving deterministic, predictable latency.

### Architectural Peak Performance

| Component | Throughput |
|---|---:|
| **SIMD_DOT instruction** | 4 INT8 MACs/instruction (vs 1 for scalar `mac8.acc`) |
| **8×8 systolic array** | Up to 64 INT8 MACs/cycle (array-level peak) |

### Instruction & Cycle Performance

| Operation | Standard RISC-V | With Garuda | Speedup |
|---|---:|---:|---:|
| Single MAC | 2 instructions | 1 instruction | 2× |
| 4-elem dot product | 16 instructions | 1 instruction | 16× (SIMD_DOT) |
| Single MAC latency | 5-8 cycles | 3-4 cycles | 1.6-2× |

### Synthesis (Area/Timing)

**Real synthesis numbers from Yosys** (generated in CI on every push/PR, clock constraint: 100 MHz / 10 ns period):

| Module | Cells (Logic) | Wires | Wire Bits | Critical Path | Est. Max Freq | Source |
|---|---:|---:|---:|---:|---:|---|
| `register_rename_table` | *CI* | *CI* | *CI* | *CI* | *CI* | [CI summary](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml) |
| `attention_microkernel_engine` | *CI* | *CI* | *CI* | *CI* | *CI* | [CI summary](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml) |
| `int8_mac_unit` | *CI* | *CI* | *CI* | *CI* | *CI* | [CI summary](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml) |
| `systolic_array` | *CI* | *CI* | *CI* | *CI* | *CI* | [CI summary](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml) |

- **Methodology**: Yosys generic synthesis (technology-agnostic); reports cells/wires/wire bits and timing (critical path, max frequency).
- **Full logs**: Available as artifact `yosys_stat` in [CI runs](https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml).
- **Note**: For FPGA/ASIC targets, use Vivado/Quartus/Design Compiler for detailed timing/power and target-specific optimizations.

---

## Features

### Custom Instructions

- **`mac8`** - INT8 MAC with 8-bit accumulator + saturation
- **`mac8.acc`** - INT8 MAC with 32-bit accumulator  
- **`mul8`** - INT8 multiply without accumulation
- **`clip8`** - Saturate to INT8 range [-128, 127]
- **`simd_dot`** - **4-element SIMD dot product** - Parallel 4×INT8 MAC with 32-bit accumulator (4× speedup)

### Architecture Highlights

- **CVXIF Interface**: Standard coprocessor protocol (no CPU changes required)
- **Stateless Design**: Supports speculative execution
- **Pipelined Execution**: 3-4 cycle latency per MAC operation
- **Overflow Detection**: Built-in saturation tracking for debugging
- **Multi-Issue Support**: Register rename table enables 4-wide instruction issue
- **Systolic Array**: Configurable 8×8 to 16×16 PE array for matrix operations

### Key Modules

- **`int8_mac_unit`**: Core MAC execution unit with SIMD_DOT support
- **`attention_microkernel_engine`**: Latency-optimized engine for attention workloads
- **`register_rename_table`**: Multi-issue rename infrastructure
- **`systolic_array`**: High-throughput matrix multiplication array

---

## Architecture

### System Overview

```
CVA6 CPU                           INT8 MAC Coprocessor
┌──────────────────────┐          ┌──────────────────────┐
│ Fetch → Decode →     │          │ Instruction Decoder  │
│ Issue → Execute → WB │◄────────►│ INT8 MAC Unit        │
└──────────────────────┘          │ Result Register      │
         CVXIF Interface          └──────────────────────┘
```

### Integration (Multi-Issue + Rename)

The `register_rename_table` is designed for a multi-issue frontend: it can rename up to 4 instructions/cycle, allocate unique physical destinations, and prevent WAW/WAR hazards by ensuring younger instructions read the *architectural* mapping (not the freshly-allocated physical reg from the same bundle).

```
Decode/Issue (4-wide)        Rename table                 Execute/Commit
┌───────────────┐      ┌──────────────────┐         ┌───────────────────┐
│ arch rs1/rs2  │ ───► │ map[arch]→phys   │ ───────►│ phys regfile      │
│ arch rd       │      │ allocate phys rd │         │ (commit frees old)│
└───────────────┘      └──────────────────┘         └───────────────────┘
```

*Evidence: `tb_register_rename_table.sv` explicitly checks "false dependency removal" for two same-cycle writes to `x5` (younger instr reads the old mapping, not the new allocation).*

### Datapath

```
rs1[7:0]  rs2[7:0]
   │         │
   └────┬────┘
        │
   ┌────▼────┐
   │ 8x8 MUL │  16-bit product
   └────┬────┘
        │
   ┌────▼────┐
   │ 32b ADD │  Accumulate
   └────┬────┘
        │
   ┌────▼────┐
   │ Pipeline│  1 cycle
   └────┬────┘
        │
     rd[31:0]
```

### Technology Details

- **INT8 Quantization**: Modern neural networks use INT8 quantization to reduce memory footprint (4× smaller than FP32), power consumption, bandwidth requirements, and hardware cost. INT8 inference achieves near-FP32 accuracy for most models with proper quantization techniques.
- **CVXIF Interface**: CVXIF provides a standard interface for RISC-V coprocessors, enabling modular accelerator design without CPU modifications. The interface handles instruction offloading, register access, and result writeback.

---

## Getting Started

### Prerequisites

- **Simulator**: Icarus Verilog (for basic simulations), Verilator/ModelSim/VCS (for advanced verification)
- **RISC-V Toolchain**: For software development (see `cva6/util/toolchain-builder`)
- **Python 3.7+**: For Cocotb verification tests
- **Git**: With submodule support

### Clone Repository

```bash
git clone https://github.com/certainly-param/garuda-accelerator.git
cd garuda-accelerator
git submodule update --init --recursive
```

### Run Simulations

**Quick verification with Icarus Verilog** (from repo root):

```bash
# Register rename table TB
iverilog -g2012 -o sim_rr.vvp garuda/tb/tb_register_rename_table.sv garuda/rtl/register_rename_table.sv
vvp sim_rr.vvp

# Multi-issue + rename integration TB
iverilog -g2012 -o sim_mi_rr_int.vvp garuda/tb/tb_multi_issue_rename_integration.sv garuda/rtl/register_rename_table.sv
vvp sim_mi_rr_int.vvp

# 2D systolic array TB
iverilog -g2012 -o sim_sa.vvp garuda/tb/tb_systolic_array.sv garuda/rtl/systolic_array.sv garuda/rtl/systolic_pe.sv
vvp sim_sa.vvp

# Attention microkernel latency microbench (p50/p95/p99)
iverilog -g2012 -o sim_att_lat.vvp garuda/rtl/attention_microkernel_engine.sv garuda/tb/tb_attention_microkernel_latency.sv
vvp sim_att_lat.vvp
```

**Advanced verification with Verilator:**

```bash
cd garuda
./run_sim.sh verilator
```

**Cocotb verification tests** (Linux/WSL):

```bash
cd garuda/dv
make
```

See `garuda/dv/README.md` for detailed verification setup instructions.

---

## Verified

This repo includes CI that runs Icarus Verilog on the SystemVerilog testbenches below.

| Testbench | Date | Simulator | Result |
|---|---:|---|---:|
| `garuda/tb/tb_register_rename_table.sv` | 2026-01-18 | Icarus Verilog 12.0 (devel) | PASS |
| `garuda/tb/tb_systolic_array.sv` | 2026-01-18 | Icarus Verilog 12.0 (devel) | PASS |
| `garuda/tb/tb_multi_issue_rename_integration.sv` | 2026-01-18 | Icarus Verilog 12.0 (devel) | PASS |
| `garuda/tb/tb_attention_microkernel_latency.sv` | 2026-01-18 | Icarus Verilog 12.0 (devel) | PASS |
| (same TBs) | CI | CI | PASS/FAIL |

- **Source of truth**: the `ci-iverilog` workflow run summary + uploaded log artifact.
  - Workflow: `https://github.com/certainly-param/garuda-accelerator/actions/workflows/ci-iverilog.yml`
  - Each run records the exact `iverilog -V` line it used and uploads `iverilog_sims_log`.

---

## Usage Examples

### Assembly Code

**Scalar Approach (4 instructions):**
```asm
# Dot product: result = a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]

dot_product_scalar:
    lw      t0, 0(a0)           # Load a[3:0] (packed INT8s)
    lw      t1, 0(a1)           # Load b[3:0] (packed INT8s)
    li      t2, 0               # Initialize accumulator
    
    mac8.acc t2, t0, t1         # acc += a[0] * b[0]
    srli     t0, t0, 8
    srli     t1, t1, 8
    
    mac8.acc t2, t0, t1         # acc += a[1] * b[1]
    srli     t0, t0, 8
    srli     t1, t1, 8
    
    mac8.acc t2, t0, t1         # acc += a[2] * b[2]
    srli     t0, t0, 8
    srli     t1, t1, 8
    
    mac8.acc t2, t0, t1         # acc += a[3] * b[3]
    
    mv       a0, t2             # Return result
    ret
```

**SIMD Approach (1 instruction - 4× faster!):**
```asm
# Dot product using SIMD_DOT: result = a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]

dot_product_simd:
    lw      t0, 0(a0)           # Load a[3:0] (packed INT8s)
    lw      t1, 0(a1)           # Load b[3:0] (packed INT8s)
    li      t2, 0               # Initialize accumulator
    
    simd_dot t2, t0, t1         # t2 = dot(a[3:0], b[3:0]) + t2
                                # Equivalent to 4 parallel MAC operations!
    
    mv       a0, t2             # Return result
    ret
```

### C with Inline Assembly

**SIMD Dot Product (4× faster):**
```c
// SIMD_DOT: Compute 4-element dot product in parallel
static inline int32_t simd_dot(int32_t acc, uint32_t a_packed, uint32_t b_packed) {
    int32_t result;
    asm volatile (
        "simd_dot %0, %1, %2"
        : "=r" (result)
        : "r" (a_packed), "r" (b_packed), "0" (acc)
    );
    return result;
}

// Optimized dot product using SIMD_DOT (4× speedup)
int32_t dot_product_simd(int8_t* a, int8_t* b, int n) {
    int32_t sum = 0;
    int i;
    
    // Process 4 elements at a time using SIMD_DOT
    for (i = 0; i < n - 3; i += 4) {
        uint32_t a_packed = *(uint32_t*)&a[i];
        uint32_t b_packed = *(uint32_t*)&b[i];
        sum = simd_dot(sum, a_packed, b_packed);
    }
    
    // Handle remaining elements with scalar MAC
    for (; i < n; i++) {
        sum = mac8_acc(sum, a[i], b[i]);
    }
    return sum;
}
```

---

## Repository Structure

```
garuda-accelerator/
├── README.md                    # This file
├── garuda/                      # Garuda accelerator RTL
│   ├── rtl/                     # RTL source files
│   │   ├── int8_mac_instr_pkg.sv        # Instruction definitions
│   │   ├── int8_mac_unit.sv             # MAC execution unit (with SIMD_DOT)
│   │   ├── int8_mac_decoder.sv          # Instruction decoder
│   │   ├── int8_mac_coprocessor.sv      # Top-level module
│   │   ├── attention_microkernel_engine.sv  # Latency-optimized engine
│   │   ├── register_rename_table.sv     # Multi-issue rename table
│   │   └── systolic_array.sv            # Systolic array implementation
│   ├── tb/                      # Testbenches
│   │   ├── tb_int8_mac_unit.sv          # MAC unit testbench
│   │   ├── tb_register_rename_table.sv  # Rename table testbench
│   │   ├── tb_systolic_array.sv         # Systolic array testbench
│   │   ├── tb_multi_issue_rename_integration.sv  # Integration testbench
│   │   └── tb_attention_microkernel_latency.sv   # Latency microbench
│   ├── dv/                      # Cocotb verification
│   │   ├── test_mac.py          # Cocotb test suite (1000 vectors)
│   │   └── Makefile             # Test runner
│   ├── synth/                   # Synthesis scripts
│   │   └── run_vivado.tcl       # Vivado synthesis script
│   └── run_sim.sh               # Simulation runner
├── .github/
│   └── workflows/
│       └── ci-iverilog.yml      # CI workflow for simulations & synthesis
└── ci/                          # CI helper scripts
    ├── run_iverilog_sims.sh     # Icarus simulation runner
    ├── parse_yosys_stats.sh     # Synthesis stats parser
    └── parse_yosys_timing.sh    # Timing analysis parser
```

---

## Synthesis (Local)

For detailed PPA (Power, Performance, Area) analysis, you can run synthesis locally:

**Option 1: Vivado (Xilinx FPGAs)**
```bash
cd garuda/synth
vivado -mode batch -source run_vivado.tcl
```
Targets Zynq-7000 FPGA (xc7z020clg400-1) and generates utilization and timing reports.

**Option 2: Yosys (Free/Open-Source)**
```bash
# Install Yosys (Ubuntu: sudo apt-get install yosys)
cd garuda/synth
yosys -p "synth_xilinx -top int8_mac_unit -flatten; write_json output.json" \
  ../rtl/int8_mac_instr_pkg.sv ../rtl/int8_mac_unit.sv
```

**Option 3: Other Tools**
- **Intel Quartus:** For Intel/Altera FPGAs
- **Synopsys Design Compiler / Cadence Genus:** For ASIC synthesis
- Or any SystemVerilog-capable synthesis tool

**Note:** CI automatically runs Yosys synthesis for all key modules on every push/PR. See the [Performance & Stats](#performance--stats) section for up-to-date numbers.

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Development setup and coding standards
- Submitting pull requests
- Adding testbenches and verification
- Documentation improvements

**Good first issues**: Check GitHub Issues tagged with `good first issue` for beginner-friendly tasks.

---

## References

**RISC-V:**
- [CV-X-IF Specification](https://github.com/openhwgroup/core-v-xif)
- [CVA6 Documentation](https://docs.openhwgroup.org/projects/cva6-user-manual/)
- [RISC-V ISA Manual](https://riscv.org/technical/specifications/)

**Neural Network Quantization:**
- [Quantization and Training of Neural Networks](https://arxiv.org/abs/1712.05877)
- [Survey of Quantization Methods](https://arxiv.org/abs/2103.13630)

---

## Use Cases

- **Real-time transformer inference**: Voice assistants, local LLM attention mechanisms
- **Edge AI**: Resource-constrained devices requiring low-latency inference
- **Research & Education**: RISC-V accelerator development, custom instruction set design
- **Hardware startups**: Foundation for specialized ML coprocessor products

---

## Contact & Community

- **GitHub Issues**: Bug reports and feature requests
- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
- **License**: Apache 2.0 (see [LICENSE](LICENSE) for details)

---

## License

- **Garuda RTL:** Apache License 2.0
- **CVA6:** Solderpad Hardware License v0.51
- **Documentation:** Creative Commons BY 4.0
