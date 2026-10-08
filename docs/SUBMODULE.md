# Using arc-dgpu-ctl from another project

## Add it

```sh
git submodule add https://github.com/Dane64/arc-dgpu-ctl external/arc-dgpu-ctl
git -C external/arc-dgpu-ctl checkout v4.0.0     # always pin a release tag
git commit -am "Add arc-dgpu-ctl v4.0.0"
```

Clone parents with `--recurse-submodules` (or `git submodule update --init`).
Update: `git -C external/arc-dgpu-ctl fetch --tags && git -C external/arc-dgpu-ctl checkout vX.Y.Z`.

Running straight from the checkout works too:
`external/arc-dgpu-ctl/src/arc-dgpu-ctl version` reads `VERSION` itself.

## Install it from the parent - pick one

**a) Parent Makefile / installer**

```make
install-arc-dgpu-ctl:
	$(MAKE) -C external/arc-dgpu-ctl install DESTDIR=$(DESTDIR) PREFIX=$(PREFIX)
```

**b) Inside the parent's .deb** - same call in `override_dh_auto_install` with
`PREFIX=/usr SYSTEMDUNITDIR=/usr/lib/systemd/system UDEVRULESDIR=/usr/lib/udev/rules.d`,
plus `Provides: arc-dgpu-ctl` and `Conflicts: arc-dgpu-ctl`.

**c) Depend on the released package** - `Depends: arc-dgpu-ctl (>= 4.0.0)`;
keep the submodule for development only. Simplest to maintain.

## CLI contract (stable within a major version)

| Item | Guarantee |
|---|---|
| `arc-dgpu-ctl state` | stdout exactly `on` or `off`; exit 0; no root needed |
| `arc-dgpu-ctl on` / `off` | exit 0 = done (also if already in that state), 1 = failed or refused (reason on stderr); root; the choice is saved and re-applied at boot unless `PERSIST=0` |
| `arc-dgpu-ctl restore` | applies the saved state; root |
| `arc-dgpu-ctl version` | `arc-dgpu-ctl X.Y.Z` |
| exit codes | 0 ok, 1 error, 2 usage error |
| env | `FORCE`, `ALLOW_UNSUPPORTED`, `PERSIST`, `VERBOSE`, `ARC_DGPU_CTL_CONF` |
| config keys | `DGPU_VGA`, `DGPU_AUD`, `GPU_DRIVER`, `SESSION_HOLDERS`, `SESSION_MEM_MAX`, `USAGE_SAMPLE`, `STRICT_IN_USE`, `RESTORE_WAIT` |
| paths | as in the README "Files" table |

`status`, `power` and `diag` output is for humans and may change - do not parse it.

## Calling it from a GUI / daemon

```python
import subprocess
state = subprocess.run(["arc-dgpu-ctl", "state"], capture_output=True, text=True, check=True).stdout.strip()
subprocess.run(["pkexec", "arc-dgpu-ctl", "off" if state == "on" else "on"], check=True)
```

The privilege boundary (polkit rule, root helper) belongs in the parent
project. arc-dgpu-ctl is userspace only, so Secure Boot needs nothing from it.
