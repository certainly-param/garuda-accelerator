SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Paths are relative to the location of this Makefile
VERILOG_SOURCES += $(PWD)/../rtl/int8_mac_instr_pkg.sv
VERILOG_SOURCES += $(PWD)/../rtl/int8_mac_unit.sv

TOPLEVEL = int8_mac_unit
MODULE = test_mac

# Extra args for Icarus to handle SystemVerilog features
COMPILE_ARGS += -g2012

include $(shell cocotb-config --makefiles)/Makefile.sim
