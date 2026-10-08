# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning:
[SemVer](https://semver.org/). The version itself lives only in `VERSION`;
headings here are release notes (the release workflow uses the matching
section, or GitHub's generated notes if there is none).

## [Unreleased]

## [4.0.0]

### Breaking changes
- The tool is installed in `bin` (`/usr/bin`, `/usr/local/bin`) instead of `sbin`, so
  `arc-dgpu-ctl state` / `status` / `power` work for normal users without sudo.
- `arc-dgpu-off.service` is replaced by `arc-dgpu-ctl.service` (`arc-dgpu-ctl restore`).
  Upgrades convert an enabled old service into saved state `off`.

### Added
- Persistent state: `on`/`off` are saved in `/var/lib/arc-dgpu-ctl/state` and re-applied at
  boot, before the display manager. `PERSIST=0` switches without saving. The unit is enabled
  on install and does nothing until `off` has been run. `status` shows the saved state.
- `restore` command; `SESSION_MEM_MAX` and `RESTORE_WAIT` config keys.

### Changed - in-use check
- Holders found by device number over all `/dev` fds (containers, renamed nodes, by-path links).
- Processes with dGPU buffers mmap'ed but no open fd are detected.
- Xorg, X, kwin_x11 and plymouthd are session holders; session holders must run from a system
  path (not `/usr/local`) and are refused above `SESSION_MEM_MAX` (default 128 MiB).
- Refuses while audio plays through the dGPU's HDMI/DP codec, and when the dGPU is bound to
  vfio-pci / pci-stub.
- Default activity sample raised to 1 s.
- `status` as a normal user no longer prints a permission error.

## [3.5.0]

First public release.

### Added
- Desktop Arc A380 / A580 / A750 / A770 support when displays run on the iGPU.
- Safety checks on `off`: active iGPU required, no monitor on the dGPU, dGPU not the boot display.
- In-use check based on DRM client usage stats (`/proc/<pid>/fdinfo`): idle compositor / logind
  handles and enumeration-only handles do not block `off`; clients with work or memory on the
  dGPU still do. `SESSION_HOLDERS`, `USAGE_SAMPLE`, `STRICT_IN_USE` config keys.
- Alchemist (DG2) PCI-ID based detection with model reporting; unlisted models need `ALLOW_UNSUPPORTED=1`.
- `status` shows the whole PCIe port chain up to the root port.
- `state`, `version`, `help` commands; man page; Debian package; CI and release workflows.

### Notes
- Audio companion detected behind the same root port as the GPU, and unbound
  before the GPU (avoids the i915 `audio power refcount` WARN).
- `on` binds drivers explicitly and clears a stale `driver_override`.
- udev rule matches Arc DG2 devices only.
