#!/usr/bin/env bash
set -euo pipefail

# Edit these two lists. Each param is "Name=value".
APPLIANCES=(
  OD-H7245-BM
  OD-H5071-BM
)
PARAMS=(
    "Logging.FlushContainer.TransientInvalidateSwitchAfterCommit=true"
    "Logging.FlushContainer.TransientPdUtilHoldMs=1000"
    "Logging.FlushContainer.TransientFwsMergeNumberThreshold=30"
    "Logging.FlushContainer.PdFwsMergeThreshold=80"
    "Logging.FlushContainer.FwsMergeNumberThreshold=200"
    "Logging.FlushContainer.MergeMinSeqTraceLagPercent=10"  
)

DO_ON="${DO_ON:-/home/cyc/ws0/cyclone/source/cyc_core/cyc_platform/src/package/cyc_helpers/do_on.sh}"

for appliance in "${APPLIANCES[@]}"; do
  for param in "${PARAMS[@]}"; do
    for node in a b; do
      echo ">> $appliance node $node: ${param%%=*} = ${param#*=}"
      bash "$DO_ON" "$appliance" "utils/dp_cli_${node}.sh" param set "${param%%=*}" "${param#*=}"
    done
  done
done
