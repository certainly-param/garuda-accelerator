#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Icarus Verilog =="
iverilog -V | sed -n '1p'
echo

run_tb() {
  local name="$1"
  local out="$2"
  shift 2
  local files=("$@")

  echo "== Running ${name} =="
  rm -f "$out"
  iverilog -g2012 -o "$out" "${files[@]}"
  vvp "$out"
  echo
}

run_tb "tb_register_rename_table" "sim_rr.vvp" \
  "garuda/tb/tb_register_rename_table.sv" \
  "garuda/rtl/register_rename_table.sv"

run_tb "tb_systolic_array" "sim_sa.vvp" \
  "garuda/tb/tb_systolic_array.sv" \
  "garuda/rtl/systolic_array.sv" \
  "garuda/rtl/systolic_pe.sv"

run_tb "tb_multi_issue_rename_integration" "sim_mi_rr_int.vvp" \
  "garuda/tb/tb_multi_issue_rename_integration.sv" \
  "garuda/rtl/register_rename_table.sv"

run_tb "tb_attention_microkernel_latency" "sim_att_lat.vvp" \
  "garuda/rtl/attention_microkernel_engine.sv" \
  "garuda/tb/tb_attention_microkernel_latency.sv"

echo "All Icarus sims PASSED."
