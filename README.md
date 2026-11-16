# VM health check

`vm-health-check.sh` checks the Linux machine on which it runs. It reports CPU
usage (sampled over one second from `/proc/stat`), memory usage (using
`MemAvailable` from `/proc/meminfo`), and usage of the filesystem mounted at
`/` (from `df`).

The VM is **Not Healthy** if any measured value is strictly greater than 60%.
A value of exactly 60% is considered healthy. If a metric cannot be collected,
the script prints an error to standard error and exits unsuccessfully rather
than guessing a status.

## Usage

```sh
chmod +x vm-health-check.sh
./vm-health-check.sh
./vm-health-check.sh --explain
./vm-health-check.sh --help
```

`--explain` (or `-e`) prints which metrics exceed the threshold, or confirms
that all measured metrics are at or below it. The default output includes the
status and all three measurements without the explanation line. Percentages
are displayed to two decimal places; health classification uses the unrounded
measured values.

For alternate procfs locations or filesystem mount points, set
`VM_HEALTH_PROC_STAT`, `VM_HEALTH_PROC_MEMINFO`, or `VM_HEALTH_ROOT_PATH`.

## Tests

Run the CLI smoke tests with:

```sh
sh tests/test_vm_health.sh
```
