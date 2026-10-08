#!/usr/bin/env bash
# Manual installer for arc-dgpu-ctl (no make needed). On Debian/Ubuntu prefer
# the .deb from GitHub Releases.
#   sudo ./install.sh [--no-udev] [--prefix /usr/local]
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root: sudo ./install.sh"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=/usr/local
WITH_UDEV=1
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-udev) WITH_UDEV=0 ;;
        --prefix)  PREFIX=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
BINDIR=$PREFIX/bin
VERSION=$(<"$HERE/VERSION")

if dpkg -s arc-dgpu-ctl >/dev/null 2>&1; then
    echo "arc-dgpu-ctl is installed as a .deb package - use apt to manage it." >&2
    exit 1
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sed "s/^VERSION=\"@VERSION@\"$/VERSION=\"$VERSION\"/" "$HERE/src/arc-dgpu-ctl" > "$tmp/arc-dgpu-ctl"
sed "s#@BINDIR@#$BINDIR#g" "$HERE/data/arc-dgpu-ctl.service.in" > "$tmp/arc-dgpu-ctl.service"

# Migrate from 3.x: binary lived in sbin (not in a normal user's PATH) and
# arc-dgpu-off.service switched off unconditionally. An enabled old service
# becomes a saved "off" state.
if [[ -e /etc/systemd/system/arc-dgpu-off.service ]]; then
    if systemctl -q is-enabled arc-dgpu-off.service 2>/dev/null; then
        mkdir -p /var/lib/arc-dgpu-ctl
        [[ -e /var/lib/arc-dgpu-ctl/state ]] || echo off > /var/lib/arc-dgpu-ctl/state
        echo "migrated: enabled arc-dgpu-off.service -> saved state 'off'"
    fi
    systemctl disable arc-dgpu-off.service 2>/dev/null || true
    rm -f /etc/systemd/system/arc-dgpu-off.service
fi
rm -f "$PREFIX/sbin/arc-dgpu-ctl"

install -Dm0755 "$tmp/arc-dgpu-ctl"          "$BINDIR/arc-dgpu-ctl"
install -Dm0644 "$tmp/arc-dgpu-ctl.service"  /etc/systemd/system/arc-dgpu-ctl.service
install -Dm0644 "$HERE/man/arc-dgpu-ctl.8"   "$PREFIX/share/man/man8/arc-dgpu-ctl.8"
[[ -f /etc/arc-dgpu-ctl.conf ]] || install -m 0644 "$HERE/data/arc-dgpu-ctl.conf" /etc/arc-dgpu-ctl.conf

if [[ $WITH_UDEV == 1 ]]; then
    install -m 0644 "$HERE/data/99-arc-dgpu-ctl.rules" /etc/udev/rules.d/99-arc-dgpu-ctl.rules
    udevadm control --reload-rules || true
else
    echo "skipping udev rule (--no-udev)"
fi
systemctl daemon-reload
# Safe to enable: it only acts after `arc-dgpu-ctl off` saved "off".
systemctl enable arc-dgpu-ctl.service

cat <<MSG

Installed arc-dgpu-ctl $VERSION to $BINDIR.

  arc-dgpu-ctl state          # no sudo needed
  sudo arc-dgpu-ctl off       # off now AND after every reboot
  sudo arc-dgpu-ctl on        # on now AND after every reboot
MSG
