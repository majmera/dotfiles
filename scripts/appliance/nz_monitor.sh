#!/bin/bash
# Monitor unique NearZero volume sessions from journalctl
# Usage: journalctl -f | grep "NZVolumeSession.hxx:DisplayStats" | bash nz_monitor.sh [-v] [interval]
#
# Options:
#   -v          Show session IDs (verbose mode)
#   interval    Interval in seconds (default 5)

VERBOSE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v) VERBOSE=1; shift ;;
        *)  INTERVAL="$1"; shift ;;
    esac
done

INTERVAL=${INTERVAL:-5}

declare -A sources
count=0
window_start=$(date +%s)

while IFS= read -r line; do
    # Extract the source UUID at the end of the line
    src=$(echo "$line" | grep -oP 'source \K[0-9a-f-]+')
    if [[ -n "$src" ]]; then
        sources["$src"]=1
        ((count++))
    fi

    now=$(date +%s)
    elapsed=$(( now - window_start ))

    if (( elapsed >= INTERVAL )); then
        ts=$(date '+%H:%M:%S')
        echo "[$ts] ${#sources[@]} unique sessions, $count log lines in ${elapsed}s"
        if (( VERBOSE )); then
            printf '%s\n' "${!sources[@]}" | sort | sed 's/^/  /'
            echo "---"
        fi
        # Reset for next window
        unset sources
        declare -A sources
        count=0
        window_start=$now
    fi
done
