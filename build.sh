#!/bin/bash
# Build the GingaNin .rbf and REFUSE to report success unless Quartus says the
# full compilation succeeded: the stale .rbf is removed first, so a failed
# build can never be mistaken for a good one (MS1BCD's lesson, 2026-09-22).
#   ./build.sh LOGFILE           full compile
#   ./build.sh LOGFILE map       analysis and synthesis only (the M10K check)
cd "$(dirname "$0")" || exit 1
LOG="${1:-build.log}"
Q=~/intelFPGA_lite_clean/17.0/quartus/bin
if [ "$2" = "map" ]; then
  # build_id.tcl only runs inside a flow; write what it would
  printf '`define BUILD_DATE "%s"' "$(date +%y%m%d)" > build_id.v
  $Q/quartus_map GingaNin > "$LOG" 2>&1; rc=$?
  grep -E "^Error|Error \(" "$LOG" | head -n 25
  grep -E "Analysis & Synthesis was successful|Total block memory bits|Total RAM" "$LOG" output_files_gn/GingaNin.map.summary 2>/dev/null
  exit $rc
fi
rm -f output_files_gn/GingaNin.rbf
$Q/quartus_sh --flow compile GingaNin > "$LOG" 2>&1
rc=$?
if grep -q "Full Compilation was successful" "$LOG" && [ -f output_files_gn/GingaNin.rbf ]; then
  echo "BUILD OK (rc=$rc)"
  grep -E "Logic utilization \(in ALMs\)|Total RAM Blocks|Total registers" output_files_gn/GingaNin.fit.rpt | head -n 3
  grep -c "Timing requirements not met" output_files_gn/GingaNin.sta.rpt | sed 's/^/timing-not-met lines: /'
  md5sum output_files_gn/GingaNin.rbf
else
  echo "BUILD FAILED (rc=$rc)"
  grep -E "^Error|Error \(" "$LOG" | head -n 25
  exit 1
fi
