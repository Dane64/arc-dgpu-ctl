# Contributing

This tool writes to PCI sysfs as root, so changes are reviewed safety-first.

```sh
make check     # shellcheck + tests (no root, no GPU needed)
make deb       # optional, needs debhelper
```

Then test on real hardware - CI cannot:

```sh
make build
sudo VERBOSE=1 build/arc-dgpu-ctl off && sudo VERBOSE=1 build/arc-dgpu-ctl on
sudo dmesg | grep -Ei 'wakeref|audio power|cut here'   # expect nothing
```

## Rules

- Bash, `set -euo pipefail`, ShellCheck-clean, no new runtime dependencies without discussion.
- **Teardown order is load-bearing**: audio → GPU → PCI remove.
- Never `die` during detection - a removed GPU is a normal state.
- Adding a PCI ID: update `DG2_IDS`/`model_of` in the script **and** the udev rule (a test checks they match).
- The CLI contract (docs/SUBMODULE.md) changes only with a `breaking-change` label and a major version.
- Add a line under `## [Unreleased]` in `CHANGELOG.md`.
