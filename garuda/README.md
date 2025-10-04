# Garuda Accelerator

RISC-V CVXIF coprocessor for high-speed INT8 multiply-accumulate operations.

## Directory Structure

```
garuda/
├── rtl/                         # RTL source files
│   ├── int8_mac_instr_pkg.sv   # Instruction definitions
│   ├── int8_mac_unit.sv        # MAC execution unit
│   ├── int8_mac_decoder.sv     # Instruction decoder
│   └── int8_mac_coprocessor.sv # Top-level module
├── tb/                          # Testbenches
│   └── tb_int8_mac_unit.sv     # MAC unit testbench
└── sw/                          # Software tests
```

## Instructions

| Instruction | Encoding | Description |
|-------------|----------|-------------|
| `mac8` | `0x0000007B` | INT8 MAC with 8-bit accumulator + saturation |
| `mac8.acc` | `0x0200007B` | INT8 MAC with 32-bit accumulator |
| `mul8` | `0x0400007B` | INT8 multiply |
| `clip8` | `0x0600007B` | Saturate to INT8 range [-128, 127] |

## Running Simulations

### Quick Start

```bash
./run_sim.sh verilator
```

### Verilator

```bash
verilator --cc --exe --build -Wall \
  --top-module tb_int8_mac_unit \
  -Irtl \
  rtl/int8_mac_instr_pkg.sv \
  rtl/int8_mac_unit.sv \
  tb/tb_int8_mac_unit.sv \
  --binary

./obj_dir/Vtb_int8_mac_unit
```

### ModelSim/Questa

```bash
vlog +incdir+rtl rtl/int8_mac_instr_pkg.sv rtl/int8_mac_unit.sv tb/tb_int8_mac_unit.sv
vsim -c tb_int8_mac_unit -do "run -all; quit"
```

### VCS

```bash
vcs -sverilog +v2k -timescale=1ns/1ps +incdir+rtl \
    rtl/int8_mac_instr_pkg.sv rtl/int8_mac_unit.sv tb/tb_int8_mac_unit.sv
./simv
```

## Module Hierarchy

```
int8_mac_coprocessor
├── int8_mac_decoder     (Pattern matching & operand extraction)
└── int8_mac_unit        (8x8 multiplier, 32-bit adder, saturation)
```

## Test Coverage

- Basic MAC operations
- Zero handling
- Negative numbers
- Saturation (upper & lower)
- Multi-step accumulation
- Edge cases (max/min values)

## CVA6 Integration

1. Add files to `cva6/Flist.ariane`
2. Instantiate `int8_mac_coprocessor` in CVA6 top
3. Connect to CVXIF interface
4. Set `CVA6ConfigCvxifEn = 1`

See CVA6 documentation and CVXIF specification for integration details.

## Resource Estimates

Per MAC unit:

- LUTs: ~200
- Registers: ~150
- Multipliers: 1x (8x8)
- Latency: 3-4 cycles
- Fmax: 100+ MHz (FPGA), 1+ GHz (ASIC)
