#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Verilator =="
verilator --version | head -n 1
echo

run_tb() {
  local name="$1"
  local top="$2"
  shift 2
  local files=("$@")

  echo "== Running ${name} =="
  rm -rf obj_dir
  
  verilator --cc --exe --build \
    --top-module "${top}" \
    -Igaruda/rtl \
    -Wno-WIDTH \
    -Wno-UNUSED \
    -Wno-TIMESCALEMOD \
    -Wno-REDEFMACRO \
    -Wno-PINCONNECTEMPTY \
    "${files[@]}" \
    --binary \
    -o "V${top}"
  
  ./obj_dir/V"${top}"
  echo
}

# Testbenches that work with Verilator
run_tb "tb_register_rename_table" "tb_register_rename_table" \
  "garuda/tb/tb_register_rename_table.sv" \
  "garuda/rtl/register_rename_table.sv"

run_tb "tb_systolic_array" "tb_systolic_array" \
  "garuda/tb/tb_systolic_array.sv" \
  "garuda/rtl/systolic_array.sv" \
  "garuda/rtl/systolic_pe.sv"

run_tb "tb_multi_issue_rename_integration" "tb_multi_issue_rename_integration" \
  "garuda/tb/tb_multi_issue_rename_integration.sv" \
  "garuda/rtl/register_rename_table.sv"

run_tb "tb_attention_microkernel_latency" "tb_attention_microkernel_latency" \
  "garuda/rtl/attention_microkernel_engine.sv" \
  "garuda/tb/tb_attention_microkernel_latency.sv"

# CVXIF integration testbench (Verilator only)
run_tb "tb_attention_microkernel_cvxif" "tb_attention_microkernel_cvxif" \
  "garuda/rtl/int8_mac_instr_pkg.sv" \
  "garuda/rtl/int8_mac_decoder.sv" \
  "garuda/rtl/int8_mac_unit.sv" \
  "garuda/rtl/attention_microkernel_engine.sv" \
  "garuda/rtl/int8_mac_coprocessor.sv" \
  "garuda/tb/tb_attention_microkernel_cvxif.sv"

echo "All Verilator sims PASSED."
