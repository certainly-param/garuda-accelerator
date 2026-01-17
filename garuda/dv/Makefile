SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Paths are relative to the location of this Makefile
VERILOG_SOURCES += $(PWD)/../rtl/int8_mac_instr_pkg.sv
VERILOG_SOURCES += $(PWD)/../rtl/int8_mac_unit.sv

TOPLEVEL = int8_mac_unit
MODULE = test_mac

# Extra args for Icarus to handle SystemVerilog features
COMPILE_ARGS += -g2012

# Windows-specific: Set Python DLL location for cocotb
# On Windows, cocotb needs to find python3.dll
ifeq ($(OS),Windows_NT)
    # Get Python DLL directory and set LIBPYTHON_LOC
    PYTHON_DIR := $(shell python -c "import sys; from pathlib import Path; print(Path(sys.executable).parent)" 2>NUL || echo "")
    ifneq ($(PYTHON_DIR),)
        # Set LIBPYTHON_LOC to point to Python DLL directory
        LIBPYTHON_LOC := $(PYTHON_DIR)
        export LIBPYTHON_LOC
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
