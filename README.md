# arc-dgpu-ctl

[![CI](https://github.com/Dane64/arc-dgpu-ctl/actions/workflows/ci.yml/badge.svg)](https://github.com/Dane64/arc-dgpu-ctl/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Dane64/arc-dgpu-ctl)](https://github.com/Dane64/arc-dgpu-ctl/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Runtime power-off for **Intel Arc Alchemist (DG2) discrete GPUs** on Linux.
`arc-dgpu-ctl off` unbinds the GPU's audio and graphics drivers in a safe order
and removes the GPU from the PCI bus so the PCIe root port can drop to D3cold;
`arc-dgpu-ctl on` brings it back without a reboot.

The Arc Alchemist **mobile** family is tested and supported on modern
Debian-based distributions.

Pure userspace bash - no kernel module, so nothing to sign for Secure Boot.

## Supported GPUs

| Family | Models | Requirement |
|---|---|---|
| **Mobile** | A350M, A370M, A530M, A550M, A570M, A730M, A770M | hybrid graphics (iGPU drives the panel) |
| **Desktop** | A380, A580, A750, A770 | **every monitor on the motherboard (iGPU) outputs**, see below |
| Other Alchemist | A310, Arc Pro, embedded | not supported; `ALLOW_UNSUPPORTED=1` to try |

Detection is by PCI ID, so Battlemage, NVIDIA, AMD and the iGPU itself are
never touched.

### Desktop cards

A desktop card can only be switched off when nothing is displayed through it:

- the CPU must have an integrated GPU (no "F" models), enabled in the BIOS,
- the BIOS primary display must be the iGPU (`IGD` / "integrated"),
- all monitors are connected to the motherboard's video outputs.

`off` checks all three and refuses otherwise (a monitor on the card, no active
iGPU, or the card being the firmware boot display).

Whether this actually **saves power depends on the motherboard**: the slot's
root port must be allowed to enter D3cold. Many desktop boards do not support
that for the x16 slot. Check `arc-dgpu-ctl status` after `off` - the last
`port :` line (the root port) must read `state=suspended`. If it stays
`active`, the card is still powered and unbound; keep it on instead and
enable PCIe ASPM in the BIOS, which is Intel's recommended idle-power setting
for desktop Arc.

> ⚠️ Do the first `off` test over SSH or from a TTY with `PERSIST=0`
> (`sudo PERSIST=0 arc-dgpu-ctl off`): then a reboot always restores the GPU.

### Persistent state

`on` and `off` remember the choice in `/var/lib/arc-dgpu-ctl/state`. At boot,
`arc-dgpu-ctl.service` runs `arc-dgpu-ctl restore`: if the saved state is
`off`, it waits for i915/xe to finish probing and switches the dGPU off
**before the display manager starts**, so Xorg / the compositor never pick it
up. The unit is enabled on install but does nothing until you have run `off`.
`PERSIST=0` switches without touching the saved state. If the boot-time `off`
is refused, the reason is in `journalctl -b -u arc-dgpu-ctl`.

### When is the GPU "in use"?

`off` does not refuse just because a DRM node of the dGPU is open. Xorg, KWin,
GNOME Shell, Xwayland, plymouth, systemd-logind and PID 1 open **every** GPU
for hotplug, and Mesa/Vulkan open every render node while enumerating GPUs.
Instead, the per-client usage stats the kernel publishes in
`/proc/<pid>/fdinfo` (`drm-engine-*`, `drm-cycles-*`, `drm-total-*`) decide.

Holders are found by **device number**: every fd of every process that points
at a `/dev` node is checked, so containers (podman/flatpak `--device`), renamed
nodes and `/dev/dri/by-path` links are caught. Processes that closed the fd
but still have dGPU buffers mapped are found via `/proc/<pid>/maps`.

| Holder | Result |
|---|---|
| engine time advances during a 1 s sample | refused (busy) |
| session process (`SESSION_HOLDERS` name **and** a binary under `/usr`, `/bin`, `/sbin`, `/lib`), idle, ≤ `SESSION_MEM_MAX` (128 MiB) | ignored |
| session process holding more than `SESSION_MEM_MAX` (it renders on the dGPU) | refused |
| other process with GPU work, memory or mapped buffers on the dGPU (ComfyUI, llama.cpp, a game with `DRI_PRIME=1`) | refused |
| other process that only opened the node, no work, no memory | allowed |
| kernel without DRM usage stats | refused (cannot prove idle) |

Also always refused: a monitor or enabled connector on the dGPU, audio playing
through the dGPU's HDMI/DP codec, and a dGPU bound to `vfio-pci`/`pci-stub`.
`VERBOSE=1` lists the ignored holders; `STRICT_IN_USE=1` in the config restores
"any open handle refuses".

## Install

### Debian / Ubuntu (.deb)

Download from [Releases](https://github.com/Dane64/arc-dgpu-ctl/releases):

```sh
sha256sum -c SHA256SUMS --ignore-missing
sudo apt install ./arc-dgpu-ctl_*_all.deb
```

```sh
arc-dgpu-ctl state                 # no sudo needed
sudo PERSIST=0 arc-dgpu-ctl off    # first test: not remembered
sudo arc-dgpu-ctl off              # off now and after every reboot
```

`apt remove arc-dgpu-ctl` turns the GPU back on before removing files;
`apt purge` also forgets the saved state. Upgrading from 3.x: an enabled
`arc-dgpu-off.service` is converted to saved state `off`.

### From source

```sh
git clone https://github.com/Dane64/arc-dgpu-ctl && cd arc-dgpu-ctl
sudo ./install.sh            # or: sudo make install
sudo ./uninstall.sh          # turns the GPU on first; --purge removes config + state
```

vfio-pci passthrough of an Arc card: install with `--no-udev` / `WITH_UDEV=0`.

### As a submodule

See [docs/SUBMODULE.md](docs/SUBMODULE.md).

## Commands

| Command | Effect |
|---|---|
| `arc-dgpu-ctl status` | state, model, drivers, PCIe port power states, draw |
| `arc-dgpu-ctl state` | prints `on` or `off` only - stable, for scripts/GUIs |
| `sudo arc-dgpu-ctl off` | safety checks, ordered teardown, PCI remove |
| `sudo arc-dgpu-ctl restore` | apply the saved state (boot service) |
| `sudo arc-dgpu-ctl on` | rescan, clear `driver_override`, rebind drivers |
| `arc-dgpu-ctl power` | power readings only |
| `sudo arc-dgpu-ctl diag` | troubleshooting dump |
| `arc-dgpu-ctl version` | version |

| Environment | Effect |
|---|---|
| `PERSIST=0` | `on`/`off` without changing the saved boot state |
| `FORCE=1` | skip the display / in-use safety checks |
| `ALLOW_UNSUPPORTED=1` | allow unlisted Alchemist models |
| `VERBOSE=1` | print each step |
| `ARC_DGPU_CTL_CONF=` | alternative config file |

Exit codes: `0` ok, `1` error, `2` usage error. See `man arc-dgpu-ctl`.

## How it works - the three kernel pitfalls

### 1. The i915 unbind WARNING

```
i915 0000:03:00.0: [drm] *ERROR* audio power refcount 1 after unbind
WARNING: drivers/gpu/drm/i915/intel_runtime_pm.c:522
i915 raw-wakerefs=1 wakelocks=1 on cleanup
```

The GPU's HDA audio function is a **separate PCI device** that binds to the
GPU through the i915 audio component and holds a display power wakeref while
bound. Unbinding i915 first tears the driver down with the wakeref still taken.

**Fix - strict teardown order:** unbind `snd_hda_intel` → unbind `i915`/`xe`
→ PCI-remove both → set the port to `power/control=auto`.

### 2. Rescan does not re-probe a driver

`echo 1 > /sys/bus/pci/rescan` re-enumerates the device but does not reliably
re-probe a driver after an explicit unbind, leaving `driver=none`.

**Fix:** `on` binds explicitly, loading the module first if needed, and waits
for the link and probe to settle.

### 3. `driver_override` set to the literal string `none`

`driver_override` pins a device to one named driver; the value `none` means
*bind to nothing*, so every bind and autoprobe is silently refused.

**Fix:** `on` clears a stale override before binding, `status`/`diag` report
it, and `99-arc-dgpu-ctl.rules` clears it on every device `add` (Arc DG2
devices only). `driver_override` does not survive a reboot - if you find it
set, something applied it during boot:

```sh
grep -rn driver_override /etc/udev/rules.d/ /lib/udev/rules.d/ /usr/lib/udev/rules.d/
```

## Measuring the power saving

What counts is the **root port** (last `port :` line) reaching
`state=suspended` after `off` - that is D3cold. Right after `on`, the port
shows `power=on state=active` by design.

- **Battery** (laptops): unplug, let each state settle ~60 s, compare
  `arc-dgpu-ctl power` with the GPU on and off.
- **On AC**: battery readings show charging, not load; RAPL covers the CPU
  package only. The GPU's own hwmon (when the driver exposes one) is the only
  software reading that sees the dGPU. hwmon is a kernel sysfs interface of i915/xe -
  no package is needed (lm-sensors is optional, only for viewing). For a whole-system number use a wall
  meter (fully charged laptop) or an inline DC meter.

## Troubleshooting

```sh
sudo arc-dgpu-ctl diag
sudo dmesg | grep -Ei 'wakeref|audio power|cut here'   # expect nothing
sudo sh -c 'echo 1 > /sys/bus/pci/rescan'              # GPU stuck off, tool gone
```

**Root port never reaches `suspended`** - firmware does not allow D3cold for
that slot, or another device shares the port. See *Desktop cards* above.

## Files

| `.deb` | manual install | Purpose |
|---|---|---|
| `/usr/bin/arc-dgpu-ctl` | `/usr/local/bin/arc-dgpu-ctl` | the tool (in every user's `PATH`) |
| `/etc/arc-dgpu-ctl.conf` | same | optional address / driver overrides |
| `/usr/lib/systemd/system/arc-dgpu-ctl.service` | `/etc/systemd/system/…` | applies the saved state at boot |
| `/var/lib/arc-dgpu-ctl/state` | same | saved state: `on` / `off` |
| `/usr/lib/udev/rules.d/99-arc-dgpu-ctl.rules` | `/etc/udev/rules.d/…` | keeps `driver_override` clear |
| `/run/arc-dgpu-ctl.port` | same | cached PCIe port path |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE) © 2026 Dane64
