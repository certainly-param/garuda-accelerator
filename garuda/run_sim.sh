#!/bin/bash
# Simulation script for INT8 MAC accelerator testbench

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "INT8 MAC Accelerator - Simulation Script"
echo "========================================="
echo

# Check if simulator is specified
SIMULATOR=${1:-verilator}

case $SIMULATOR in
    verilator)
        echo -e "${YELLOW}Using Verilator${NC}"
        echo
        
        # Check if verilator is installed
        if ! command -v verilator &> /dev/null; then
            echo -e "${RED}Error: Verilator not found${NC}"
            echo "Install with: sudo apt-get install verilator (Ubuntu/Debian)"
            echo "            : brew install verilator (macOS)"
            exit 1
        fi
        
        # Clean previous build
        rm -rf obj_dir
        
        # Run verilator
        echo "Compiling with Verilator..."
        verilator --cc --exe --build -Wall \
          --no-timing \
          --top-module tb_int8_mac_unit \
          -Irtl \
          rtl/int8_mac_instr_pkg.sv \
          rtl/int8_mac_unit.sv \
          tb/tb_int8_mac_unit.sv \
          --binary \
          -Wno-WIDTH \
          -Wno-UNUSED \
          -Wno-TIMESCALEMOD \
          -Wno-REDEFMACRO
        
        echo
        echo "Running simulation..."
        echo "----------------------------------------"
        ./obj_dir/Vtb_int8_mac_unit
        SIM_RESULT=$?
        echo "----------------------------------------"
        ;;
    
    modelsim|questa)
        echo -e "${YELLOW}Using ModelSim/Questa${NC}"
        echo
        
        # Check if vsim is installed
        if ! command -v vsim &> /dev/null; then
            echo -e "${RED}Error: ModelSim/Questa not found${NC}"
            exit 1
        fi
        
        # Clean previous build
        rm -rf work
        
        # Create library
        vlib work
        
        # Compile
        echo "Compiling with vlog..."
        vlog +incdir+rtl \
          rtl/int8_mac_instr_pkg.sv \
          rtl/int8_mac_unit.sv \
          tb/tb_int8_mac_unit.sv
        
        echo
        echo "Running simulation..."
        echo "----------------------------------------"
        vsim -c tb_int8_mac_unit -do "run -all; quit -f"
        SIM_RESULT=$?
        echo "----------------------------------------"
        ;;
    
    vcs)
        echo -e "${YELLOW}Using VCS${NC}"
        echo
        
        # Check if vcs is installed
        if ! command -v vcs &> /dev/null; then
            echo -e "${RED}Error: VCS not found${NC}"
            exit 1
        fi
        
        # Clean previous build
        rm -rf simv* csrc DVEfiles
        
        # Compile and elaborate
        echo "Compiling with VCS..."
        vcs -sverilog +v2k \
          -timescale=1ns/1ps \
          +incdir+rtl \
          -debug_access+all \
          rtl/int8_mac_instr_pkg.sv \
          rtl/int8_mac_unit.sv \
          tb/tb_int8_mac_unit.sv
        
        echo
        echo "Running simulation..."
        echo "----------------------------------------"
        ./simv
        SIM_RESULT=$?
        echo "----------------------------------------"
        ;;
    
    iverilog)
        echo -e "${YELLOW}Using Icarus Verilog${NC}"
        echo
        
        # Check if iverilog is installed
        if ! command -v iverilog &> /dev/null; then
            echo -e "${RED}Error: Icarus Verilog not found${NC}"
            exit 1
        fi
        
        # Clean previous build
        rm -f tb_int8_mac_unit.vvp
        
        # Compile
        echo "Compiling with iverilog..."
        iverilog -g2012 \
          -I rtl \
          -o tb_int8_mac_unit.vvp \
          rtl/int8_mac_instr_pkg.sv \
          rtl/int8_mac_unit.sv \
          tb/tb_int8_mac_unit.sv
        
        echo
        echo "Running simulation..."
        echo "----------------------------------------"
        vvp tb_int8_mac_unit.vvp
        SIM_RESULT=$?
        echo "----------------------------------------"
        
        # Cleanup
        rm -f tb_int8_mac_unit.vvp
        ;;
    
    *)
        echo -e "${RED}Error: Unknown simulator '$SIMULATOR'${NC}"
        echo
        echo "Usage: $0 [simulator]"
        echo
        echo "Supported simulators:"
        echo "  verilator  - Verilator (open-source, default)"
        echo "  iverilog   - Icarus Verilog (open-source)"
        echo "  modelsim   - ModelSim/Questa"
        echo "  vcs        - Synopsys VCS"
        echo
        echo "Example: $0 iverilog"
        exit 1
        ;;
esac

# Check simulation result
echo
if [ $SIM_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Simulation completed successfully!${NC}"
else
    echo -e "${RED}✗ Simulation failed with exit code $SIM_RESULT${NC}"
    exit $SIM_RESULT
fi

echo

