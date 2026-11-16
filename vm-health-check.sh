#!/bin/sh

set -eu
LC_ALL=C
export LC_ALL

THRESHOLD=60
PROC_STAT=${VM_HEALTH_PROC_STAT:-/proc/stat}
PROC_MEMINFO=${VM_HEALTH_PROC_MEMINFO:-/proc/meminfo}
ROOT_PATH=${VM_HEALTH_ROOT_PATH:-/}

usage() {
    cat <<'EOF'
Usage: vm-health-check.sh [--explain] [--help]

Check CPU, memory, and root-filesystem usage on this Linux machine.
  -e, --explain  Include the reason for the health classification.
  -h, --help     Show this help.
EOF
}

error() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

read_cpu_counters() {
    awk '
        NR == 1 && $1 == "cpu" {
            total = 0
            for (i = 2; i <= NF && i <= 9; i++) total += $i
            idle = $5 + $6
            if (NF < 5 || total <= 0) exit 1
            printf "%.0f %.0f\n", total, idle
            found = 1
        }
        END {
            if (!found) exit 1
        }
    ' "$PROC_STAT"
}

measure_cpu() {
    before=$(read_cpu_counters) || error "could not read CPU counters from $PROC_STAT"
    set -- $before
    total_before=$1
    idle_before=$2

    sleep 1 || error 'could not wait between CPU samples'

    after=$(read_cpu_counters) || error "could not read CPU counters from $PROC_STAT"
    set -- $after
    total_after=$1
    idle_after=$2

    awk -v total_before="$total_before" -v idle_before="$idle_before" \
        -v total_after="$total_after" -v idle_after="$idle_after" '
        BEGIN {
            total_delta = total_after - total_before
            idle_delta = idle_after - idle_before
            if (total_delta <= 0 || idle_delta < 0 || idle_delta > total_delta) exit 1
            printf "%.6f\n", 100 * (total_delta - idle_delta) / total_delta
        }
    ' || error 'could not calculate CPU usage from /proc/stat samples'
}

measure_memory() {
    awk '
        $1 == "MemTotal:" { total = $2; have_total = 1 }
        $1 == "MemAvailable:" { available = $2; have_available = 1 }
        END {
            if (!have_total || !have_available || total <= 0 ||
                available < 0 || available > total) exit 1
            printf "%.6f\n", 100 * (total - available) / total
        }
    ' "$PROC_MEMINFO" || error "could not calculate memory usage from $PROC_MEMINFO"
}

measure_disk() {
    df -P "$ROOT_PATH" | awk '
        NR == 2 {
            usage = $5
            sub(/%$/, "", usage)
            if (usage !~ /^[0-9]+$/) exit 1
            printf "%.6f\n", usage
            found = 1
        }
        END {
            if (!found) exit 1
        }
    ' || error "could not determine filesystem usage for $ROOT_PATH with df"
}

is_over_threshold() {
    awk -v usage="$1" -v threshold="$THRESHOLD" 'BEGIN { exit !(usage > threshold) }'
}

display_usage() {
    awk -v usage="$1" 'BEGIN { printf "%.2f", usage }'
}

explain=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        -e|--explain)
            explain=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            error "unknown argument: $1"
            ;;
    esac
    shift
done

cpu_usage=$(measure_cpu)
memory_usage=$(measure_memory)
disk_usage=$(measure_disk)

cpu_display=$(display_usage "$cpu_usage")
memory_display=$(display_usage "$memory_usage")
disk_display=$(display_usage "$disk_usage")

reasons=
if is_over_threshold "$cpu_usage"; then
    reasons='CPU usage'
fi
if is_over_threshold "$memory_usage"; then
    if [ -n "$reasons" ]; then reasons="$reasons, "; fi
    reasons="${reasons}memory usage"
fi
if is_over_threshold "$disk_usage"; then
    if [ -n "$reasons" ]; then reasons="$reasons, "; fi
    reasons="${reasons}disk usage ($ROOT_PATH)"
fi

if [ -n "$reasons" ]; then
    printf 'Health: Not Healthy\n'
else
    printf 'Health: Healthy\n'
fi
printf 'CPU usage: %s%%\n' "$cpu_display"
printf 'Memory usage: %s%%\n' "$memory_display"
printf 'Disk usage (%s): %s%%\n' "$ROOT_PATH" "$disk_display"

if [ "$explain" = true ]; then
    if [ -n "$reasons" ]; then
        printf 'Explanation: The following metrics are above the %s%% threshold: %s.\n' "$THRESHOLD" "$reasons"
    else
        printf 'Explanation: All measured metrics are at or below the %s%% threshold.\n' "$THRESHOLD"
    fi
fi
