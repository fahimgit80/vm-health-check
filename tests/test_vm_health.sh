#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$script_dir/vm-health-check.sh"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vm-health-check.XXXXXX")
trap 'rm -rf "$temp_dir"' 0 HUP INT TERM
mkdir "$temp_dir/bin"

cat > "$temp_dir/bin/sleep" <<'EOF'
#!/bin/sh
cp "$VM_HEALTH_TEST_AFTER_STAT" "$VM_HEALTH_PROC_STAT"
EOF
cat > "$temp_dir/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'fixture 100 60 40 %s%% %s\n' "$VM_HEALTH_TEST_DISK_USAGE" "$2"
EOF
chmod +x "$temp_dir/bin/sleep" "$temp_dir/bin/df"

help_output=$(sh "$script" --help)
printf '%s\n' "$help_output" | grep -q 'Usage: vm-health-check.sh'

if sh "$script" --invalid >/dev/null 2>&1; then
    printf 'Expected an invalid argument to fail.\n' >&2
    exit 1
fi

cat > "$temp_dir/stat-initial" <<'EOF'
cpu 100 0 100 800 0
EOF
cat > "$temp_dir/stat-exact" <<'EOF'
cpu 700 0 100 1200 0
EOF
cat > "$temp_dir/stat-over" <<'EOF'
cpu 710 0 100 1190 0
EOF
cat > "$temp_dir/meminfo-exact" <<'EOF'
MemTotal: 1000 kB
MemAvailable: 400 kB
EOF
cat > "$temp_dir/meminfo-over" <<'EOF'
MemTotal: 1000 kB
MemAvailable: 390 kB
EOF
cat > "$temp_dir/meminfo-slightly-over" <<'EOF'
MemTotal: 100000 kB
MemAvailable: 39960 kB
EOF

run_check() {
    cp "$temp_dir/stat-initial" "$temp_dir/stat-before"
    VM_HEALTH_PROC_STAT="$temp_dir/stat-before" \
    VM_HEALTH_PROC_MEMINFO="$1" \
    VM_HEALTH_ROOT_PATH=/fixture \
    VM_HEALTH_TEST_AFTER_STAT="$2" \
    VM_HEALTH_TEST_DISK_USAGE="$3" \
    PATH="$temp_dir/bin:$PATH" \
        sh "$script" --explain
}

healthy=$(run_check "$temp_dir/meminfo-exact" "$temp_dir/stat-exact" 60)
printf '%s\n' "$healthy" | grep -q '^Health: Healthy$'
printf '%s\n' "$healthy" | grep -q '^CPU usage: 60\.00%$'
printf '%s\n' "$healthy" | grep -q '^Memory usage: 60\.00%$'
printf '%s\n' "$healthy" | grep -q '^Disk usage (/fixture): 60\.00%$'
printf '%s\n' "$healthy" | grep -q '^Explanation: All measured metrics are at or below the 60% threshold\.$'

unhealthy=$(run_check "$temp_dir/meminfo-over" "$temp_dir/stat-over" 61)
printf '%s\n' "$unhealthy" | grep -q '^Health: Not Healthy$'
printf '%s\n' "$unhealthy" | grep -q '^CPU usage: 61\.00%$'
printf '%s\n' "$unhealthy" | grep -q '^Memory usage: 61\.00%$'
printf '%s\n' "$unhealthy" | grep -q '^Disk usage (/fixture): 61\.00%$'
printf '%s\n' "$unhealthy" | grep -Fq 'above the 60% threshold: CPU usage, memory usage, disk usage (/fixture).'

slightly_over=$(run_check "$temp_dir/meminfo-slightly-over" "$temp_dir/stat-exact" 60)
printf '%s\n' "$slightly_over" | grep -q '^Health: Not Healthy$'
printf '%s\n' "$slightly_over" | grep -q '^Memory usage: 60\.04%$'
printf '%s\n' "$slightly_over" | grep -q 'above the 60% threshold: memory usage\.$'

cp "$temp_dir/stat-initial" "$temp_dir/stat-before"
if collection_error=$(
    VM_HEALTH_PROC_STAT="$temp_dir/stat-before" \
    VM_HEALTH_PROC_MEMINFO="$temp_dir/missing-meminfo" \
    VM_HEALTH_TEST_AFTER_STAT="$temp_dir/stat-exact" \
    PATH="$temp_dir/bin:$PATH" \
        sh "$script" 2>&1
); then
    printf 'Expected a missing memory metrics file to fail.\n' >&2
    exit 1
fi
printf '%s\n' "$collection_error" | grep -q '^Error: could not calculate memory usage from'

printf 'VM health check CLI tests passed.\n'
