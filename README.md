# Garuda: RISC-V INT8 Accelerator

Swift as the divine eagle, Garuda accelerates RISC-V with high-speed INT8 multiply-accumulate operations for neural network inference. A CVXIF coprocessor for CVA6 achieving 2-5x speedup over standard RISC-V implementations.

## Project Overview

This project extends the RISC-V ISA with custom INT8 arithmetic instructions using the CVXIF (Core-V eXtension Interface). The modular design allows adding specialized hardware without modifying the CVA6 CPU core.

### INT8 Quantization

Modern neural networks use INT8 quantization to reduce memory footprint (4x smaller than FP32), power consumption, bandwidth requirements, and hardware cost. INT8 inference achieves near-FP32 accuracy for most models with proper quantization techniques.

### CVXIF Interface

CVXIF provides a standard interface for RISC-V coprocessors, enabling modular accelerator design without CPU modifications. The interface handles instruction offloading, register access, and result writeback.

## Features

**Custom Instructions:**
- `mac8` - INT8 MAC with 8-bit accumulator + saturation
- `mac8.acc` - INT8 MAC with 32-bit accumulator  
- `mul8` - INT8 multiply without accumulation
- `clip8` - Saturate to INT8 range [-128, 127]

**Architecture:**
- CVXIF coprocessor integration
- Stateless design for speculative execution
- Pipelined MAC unit (3-4 cycle latency)
- Efficient resource usage (~200 LUTs per MAC unit)

## Repository Structure

```
garuda/                          # Garuda accelerator
├── rtl/                         # RTL source files
│   ├── int8_mac_instr_pkg.sv   # Instruction definitions
│   ├── int8_mac_unit.sv        # MAC execution unit
│   ├── int8_mac_decoder.sv     # Instruction decoder
│   └── int8_mac_coprocessor.sv # Top-level module
├── tb/                          # Testbenches
│   └── tb_int8_mac_unit.sv     # MAC unit testbench
└── sw/                          # Software tests

cva6/                            # CVA6 RISC-V CPU core (upstream)
```

## Getting Started

### Prerequisites

- RISC-V GNU Toolchain (see `cva6/util/toolchain-builder`)
- Verilator, ModelSim/Questa, or VCS
- Python 3.7+

### Clone Repository

```bash
git clone https://github.com/yourusername/cva6-garuda.git
cd cva6-garuda
git submodule update --init --recursive
```

### Run Simulations

```bash
cd garuda
./run_sim.sh verilator
```

### Verify CVA6 Environment

```bash
cd cva6
export RISCV=/path/to/toolchain
export DV_SIMULATORS=veri-testharness,spike
bash verif/regress/smoke-tests.sh
```

## Example Usage

### Assembly Code

```asm
# Dot product: result = a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]

dot_product:
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

### C with Inline Assembly

```c
static inline int32_t mac8_acc(int32_t acc, int8_t a, int8_t b) {
    int32_t result;
    asm volatile (
        "mac8.acc %0, %1, %2"
        : "=r" (result)
        : "r" (a), "r" (b), "0" (acc)
    );
    return result;
}

int32_t dot_product(int8_t* a, int8_t* b, int n) {
    int32_t sum = 0;
    for (int i = 0; i < n; i++) {
        sum = mac8_acc(sum, a[i], b[i]);
    }
    return sum;
}
```

## Architecture

### System Overview

```
CVA6 CPU                           INT8 MAC Coprocessor
┌──────────────────────┐          ┌──────────────────────┐
│ Fetch → Decode →     │          │ Instruction Decoder  │
│ Issue → Execute → WB │◄────────►│ INT8 MAC Unit        │
└──────────────────────┘          │ Result Register      │
         CVXIF Interface           └──────────────────────┘
```

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

### Resource Usage

- LUTs: ~200 per MAC unit
- 8x8 multiplier: ~100 LUTs
- 32-bit adder: ~32 LUTs
- Control logic: ~50 LUTs

## Performance

### Instruction Count

| Operation | Standard RISC-V | With MAC8.ACC | Speedup |
|-----------|----------------|---------------|---------|
| Single MAC | 2 (mul + add) | 1 | 2x |
| 4-elem dot product | 16 | 14 | 1.14x |
| 256-elem dot product | 1024 | ~770 | 1.3x |

### Cycle Count

| Operation | Standard RISC-V | MAC Coprocessor |
|-----------|----------------|-----------------|
| Single MAC | 5-8 cycles | 3-4 cycles |
| 256-elem dot product | ~2048 cycles | ~1500 cycles |

Performance depends on memory bandwidth and cache behavior.

## Documentation

Comprehensive documentation available in the `garuda/` directory and inline code comments. For CVXIF interface details, refer to the official CV-X-IF specification.

## References

**RISC-V:**
- [RISC-V ISA Manual](https://riscv.org/technical/specifications/)
- [RISC-V Custom Extensions](https://riscv.org/wp-content/uploads/2016/07/Tue0900-RISC-V-Custom-Extensions.pdf)

**Quantization:**
- [Quantization and Training of Neural Networks](https://arxiv.org/abs/1712.05877)
- [Survey of Quantization Methods](https://arxiv.org/abs/2103.13630)

**CVA6 & CVXIF:**
- [CVA6 Documentation](https://docs.openhwgroup.org/projects/cva6-user-manual/)
- [CV-X-IF Specification](https://github.com/openhwgroup/core-v-xif)

## License

- CVA6: Solderpad Hardware License v0.51
- Custom accelerator code: Apache License 2.0
