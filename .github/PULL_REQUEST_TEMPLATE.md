## What / why

<!-- Fixes #123 -->

## Checklist

- [ ] `make check` passes (shellcheck + tests)
- [ ] Tested on hardware: `sudo arc-dgpu-ctl off && sudo arc-dgpu-ctl on`, no `cut here` in dmesg (GPU / kernel: …)
- [ ] `CHANGELOG.md` updated under **[Unreleased]**
- [ ] README / man page updated if behaviour changed
- [ ] CLI contract unchanged - or labelled `breaking-change`
