#!/usr/bin/env bash
# Uninstaller for a manual (install.sh / make install) arc-dgpu-ctl install.
# Re-enables the dGPU FIRST: without the tool, only a reboot or
# `echo 1 > /sys/bus/pci/rescan` brings a PCI-removed GPU back.
#   sudo ./uninstall.sh [--purge]
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root: sudo ./uninstall.sh"; exit 1; }

if dpkg -s arc-dgpu-ctl >/dev/null 2>&1; then
    echo "arc-dgpu-ctl is installed as a .deb - run: sudo apt remove arc-dgpu-ctl" >&2
    exit 1
fi

echo "== restoring the dGPU before removing anything =="
systemctl disable arc-dgpu-ctl.service arc-dgpu-off.service 2>/dev/null || true
bin=$(command -v arc-dgpu-ctl || true)
if [[ -n $bin ]]; then PERSIST=0 "$bin" on || true; else echo 1 > /sys/bus/pci/rescan || true; fi
sleep 1

echo "== removing files =="
rm -f /etc/systemd/system/arc-dgpu-ctl.service \
      /etc/systemd/system/arc-dgpu-off.service \
      /usr/local/bin/arc-dgpu-ctl \
      /usr/local/sbin/arc-dgpu-ctl \
      /usr/local/share/man/man8/arc-dgpu-ctl.8 \
      /etc/udev/rules.d/99-arc-dgpu-ctl.rules \
      /run/arc-dgpu-ctl.port

systemctl daemon-reload
systemctl reset-failed arc-dgpu-ctl.service arc-dgpu-off.service 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true

if [[ ${1:-} == --purge ]]; then
    rm -f /etc/arc-dgpu-ctl.conf; rm -rf /var/lib/arc-dgpu-ctl
    echo "removed /etc/arc-dgpu-ctl.conf and the saved state"
else
    echo "kept /etc/arc-dgpu-ctl.conf and /var/lib/arc-dgpu-ctl (use --purge to remove them)"
fi
echo "Done."
