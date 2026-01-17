#!/usr/bin/env bash
# Parse Yosys stat output and extract key numbers
# Usage: yosys -p "read_verilog -sv MODULE.sv; synth -top TOP; stat" 2>&1 | bash ci/parse_yosys_stats.sh MODULE_NAME

set -euo pipefail

MODULE_NAME="${1:-unknown}"

# Yosys stat output format:
#   Number of cells:                123
#   Number of wires:                456
#   Number of wire bits:            789

CELLS=""
WIRES=""
WIRE_BITS=""

while IFS= read -r line; do
  # Yosys stat output uses tabs/spaces before the number
  if echo "$line" | grep -q "Number of cells:"; then
    CELLS=$(echo "$line" | awk -F':' '{print $2}' | tr -d ' \t')
  elif echo "$line" | grep -q "Number of wires:"; then
    WIRES=$(echo "$line" | awk -F':' '{print $2}' | tr -d ' \t')
  elif echo "$line" | grep -q "Number of wire bits:"; then
    WIRE_BITS=$(echo "$line" | awk -F':' '{print $2}' | tr -d ' \t')
  fi
done

# Output in a parseable format
if [ -n "$CELLS" ]; then
  echo "${MODULE_NAME}_CELLS=${CELLS}"
fi
if [ -n "$WIRES" ]; then
  echo "${MODULE_NAME}_WIRES=${WIRES}"
fi
if [ -n "$WIRE_BITS" ]; then
  echo "${MODULE_NAME}_WIRE_BITS=${WIRE_BITS}"
fi

# Note: For timing analysis, see ci/parse_yosys_timing.sh
