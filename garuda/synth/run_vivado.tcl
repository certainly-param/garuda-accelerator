# Vivado Synthesis Script for Garuda Accelerator
# Usage: vivado -mode batch -source run_vivado.tcl

# 1. Settings
set TOP_MODULE "int8_mac_unit"
set OUTPUT_DIR "./output"
# Target Part: Zynq-7000 (common in PYNQ/ZedBoard)
set PART "xc7z020clg400-1" 

# 2. Setup Project (in memory)
create_project -in_memory -part $PART
file mkdir $OUTPUT_DIR

# 3. Read Sources
puts "Reading RTL sources..."
read_verilog -sv "../rtl/int8_mac_instr_pkg.sv"
read_verilog -sv "../rtl/int8_mac_unit.sv"

# 4. Read Constraints (Optional - create a virtual clock)
# We define a 500MHz clock (2.0ns period) to stress test timing
create_clock -name clk -period 2.0 [get_ports clk_i]

# 5. Run Synthesis
puts "Running Synthesis..."
synth_design -top $TOP_MODULE -part $PART -flatten_hierarchy rebuilt

# 6. Report Results
puts "Writing Reports..."
report_utilization -file "${OUTPUT_DIR}/utilization.rpt"
report_timing_summary -file "${OUTPUT_DIR}/timing.rpt"

# 7. Check for Latch Inference (Bad!)
set latches [get_cells -hier -filter {REF_NAME =~ LD*}]
if {[llength $latches] > 0} {
    puts "CRITICAL WARNING: Latches inferred!"
    foreach l $latches {
        puts [get_property NAME $l]
    }
} else {
    puts "Success: No latches inferred."
}

puts "Done!"
