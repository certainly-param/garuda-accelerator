#!/usr/bin/env bash
# Parse Yosys timing check output and extract critical path metrics
# Usage: yosys -p "read_verilog -sv MODULE.sv; synth -top TOP; clock -period PERIOD clk_i; check" 2>&1 | bash ci/parse_yosys_timing.sh MODULE_NAME

set -euo pipefail

MODULE_NAME="${1:-unknown}"

# Yosys check output format varies, but we look for:
# - Critical path delay
# - Max frequency
# - Setup/hold violations

CRITICAL_PATH=""
MAX_FREQ=""
VIOLATIONS=""

while IFS= read -r line; do
  # Look for critical path information
  # Format varies: "Found clock period of X ns", "Longest path: X ns", etc.
  if echo "$line" | grep -qiE "(critical|longest).*path.*[0-9]+\s*(ns|ps)"; then
    CRITICAL_PATH=$(echo "$line" | grep -oE "[0-9]+\.[0-9]+" | head -n 1 || echo "")
  fi
  
  # Look for max frequency (derived from critical path or explicit)
  if echo "$line" | grep -qiE "(max|maximum).*freq.*[0-9]+"; then
    MAX_FREQ=$(echo "$line" | grep -oE "[0-9]+\.[0-9]+" | head -n 1 || echo "")
  fi
  
  # Look for timing violations
  if echo "$line" | grep -qiE "(violation|fails|failed)"; then
    VIOLATIONS="YES"
  fi
done

# Also try to extract from check summary
# Yosys check output often has lines like:
#   Check passed
#   Check failed: longest path = X ns
#   Estimated max frequency: X MHz

# Output in a parseable format
if [ -n "$CRITICAL_PATH" ]; then
  echo "${MODULE_NAME}_CRITICAL_PATH_NS=${CRITICAL_PATH}"
fi

if [ -n "$MAX_FREQ" ]; then
  echo "${MODULE_NAME}_MAX_FREQ_MHZ=${MAX_FREQ}"
fi

if [ -n "$VIOLATIONS" ]; then
  echo "${MODULE_NAME}_TIMING_VIOLATIONS=${VIOLATIONS}"
fi

# If we found critical path, calculate frequency
if [ -n "$CRITICAL_PATH" ]; then
  # Frequency = 1000 / period_ns (convert ns to MHz)
  FREQ_MHZ=$(echo "scale=2; 1000 / $CRITICAL_PATH" | bc 2>/dev/null || echo "")
  if [ -n "$FREQ_MHZ" ]; then
    echo "${MODULE_NAME}_EST_FREQ_MHZ=${FREQ_MHZ}"
  fi
fi
