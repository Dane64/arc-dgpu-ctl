#!/usr/bin/env bash
# Tests that run without root and without an Arc GPU (CI-safe).
# Nothing here writes to the real sysfs.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SRC=src/arc-dgpu-ctl
BIN=build/arc-dgpu-ctl          # built by `make build` (version substituted)
[[ -x $BIN ]] || { echo "run 'make build' first"; exit 1; }
export ARC_DGPU_CTL_CONF=/nonexistent/arc-dgpu-ctl.conf
VERSION=$(<VERSION)
pass=0 fail=0
ok()  { echo "ok   - $1"; pass=$((pass+1)); }
nok() { echo "FAIL - $1"; fail=$((fail+1)); }
t()   { local n=$1; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else nok "$n"; fi; }
tn()  { local n=$1; shift; if "$@" >/dev/null 2>&1; then nok "$n"; else ok "$n"; fi; }   # expect failure

# --- CLI ------------------------------------------------------------------
t "syntax"                     bash -n "$SRC"
t "built version == VERSION"   [ "$("$BIN" version)" = "arc-dgpu-ctl $VERSION" ]
t "source tree reads VERSION"  [ "$("$SRC" version)" = "arc-dgpu-ctl $VERSION" ]
t "no version literal in src"  grep -q '^VERSION="@VERSION@"$' "$SRC"
t "help exits 0"               "$BIN" help
"$BIN" bogus >/dev/null 2>&1;  t "unknown command exits 2" [ $? -eq 2 ]
st=$("$BIN" state); rc=$?
t "state exits 0"              [ $rc -eq 0 ]
if [[ $st == on || $st == off ]]; then ok "state prints on|off ($st)"; else nok "state prints on|off ($st)"; fi
if [[ $EUID -ne 0 ]]; then
    out=$("$BIN" off 2>&1); rc=$?
    if [[ $rc -eq 1 && $out == *"must be run as root"* ]]; then ok "off refuses non-root"; else nok "off refuses non-root"; fi
    out=$("$BIN" on 2>&1); rc=$?
    if [[ $rc -eq 1 && $out == *"must be run as root"* ]]; then ok "on refuses non-root"; else nok "on refuses non-root"; fi
fi
t "status exits 0"             "$BIN" status

# --- device classification against a fake sysfs ---------------------------
FAKE=$(mktemp -d); trap 'rm -rf "$FAKE"' EXIT
mkdev() { mkdir -p "$FAKE/$1"; echo "$2" > "$FAKE/$1/vendor"; echo "$3" > "$FAKE/$1/device"; }
mkdev igpu      0x8086 0xa7a0      # Raptor Lake iGPU
mkdev a730m     0x8086 0x5691
mkdev a770      0x8086 0x56A0      # uppercase hex as some kernels print it
mkdev a310      0x8086 0x56a6
mkdev bmg       0x8086 0xe20b      # Battlemage - not Alchemist
mkdev nvidia    0x10de 0x2860
# shellcheck source=src/arc-dgpu-ctl
. "$SRC"
set +euo pipefail                  # the script enables these; tests must not abort
sysdev() { echo "$FAKE/$1"; }
tn "iGPU not detected"          is_alchemist "$FAKE/igpu"
tn "Battlemage not detected"    is_alchemist "$FAKE/bmg"
tn "NVIDIA not detected"        is_alchemist "$FAKE/nvidia"
t "A730M detected"             is_alchemist "$FAKE/a730m"
t "A770 detected (uppercase)"  is_alchemist "$FAKE/a770"
t "A730M tier mobile"          [ "$(model_of a730m)" = "mobile Arc A730M" ]
t "A770 tier desktop"          [ "$(model_of a770)" = "desktop Arc A770" ]
t "A310 tier unlisted"         [ "$(model_of a310 | cut -d' ' -f1)" = unlisted ]

# --- in-use check against a fake /proc ------------------------------------
# fds are symlinks to /dev/null (char 1:3) = the "dGPU" node; /dev/zero (1:5)
# stands for some other device. Holders are matched by device number.
mkdir -p "$FAKE/dgpu/drm/card1" "$FAKE/dgpu/drm/renderD129"
echo 1:3 > "$FAKE/dgpu/drm/card1/dev"; echo 1:3 > "$FAKE/dgpu/drm/renderD129/dev"
DGPU_VGA=dgpu; PROC_ROOT=$FAKE/proc; USAGE_SAMPLE=0
mkproc() {   # mkproc <pid> <comm> <fdinfo> [exe] [devnode]
    mkdir -p "$PROC_ROOT/$1/fd" "$PROC_ROOT/$1/fdinfo"
    echo "$2" > "$PROC_ROOT/$1/comm"
    ln -sfn "${4:-/usr/bin/$2}" "$PROC_ROOT/$1/exe"
    ln -sf "${5:-/dev/null}" "$PROC_ROOT/$1/fd/9"
    printf '%b' "$3" > "$PROC_ROOT/$1/fdinfo/9"
}
I915='drm-driver:\ti915\ndrm-pdev:\t0000:03:00.0\ndrm-client-id:\t7\n'
reset_proc() { rm -rf "$PROC_ROOT"; mkdir -p "$PROC_ROOT"; }
sample_wait() { :; }

reset_proc
t  "no holders -> free"                   check_users
mkproc 1    systemd        "$I915" /usr/lib/systemd/systemd
mkproc 982  systemd-logind "$I915" /usr/lib/systemd/systemd-logind
mkproc 1577 kwin_wayland   "${I915}drm-engine-render:\t81234 ns\ndrm-total-local0:\t4 MiB\n"
mkproc 1629 Xwayland       "$I915"
t  "idle session holders ignored"         check_users
reset_proc
mkproc 1125 Xorg           "${I915}drm-engine-render:\t5000 ns\ndrm-total-local0:\t10 MiB\n" /usr/lib/xorg/Xorg
t  "idle Xorg with 10 MiB ignored (reported case)" check_users
reset_proc
mkproc 1125 Xorg           "${I915}drm-total-local0:\t10 MiB\n" "/usr/lib/xorg/Xorg (deleted)"
t  "Xorg binary replaced by upgrade still trusted" check_users
reset_proc
mkproc 1125 Xorg           "${I915}drm-total-local0:\t900 MiB\n" /usr/lib/xorg/Xorg
tn "session holder above SESSION_MEM_MAX refused" check_users
reset_proc
mkproc 5000 Xorg           "${I915}drm-total-local0:\t64 MiB\n" /home/u/bin/Xorg
tn "fake 'Xorg' outside system paths refused" check_users
reset_proc
mkproc 5001 X              "${I915}drm-total-local0:\t64 MiB\n" /usr/local/bin/X
tn "session name from /usr/local refused"  check_users
reset_proc
mkproc 3000 firefox-bin    "${I915}drm-engine-render:\t0 ns\ndrm-total-system0:\t0\n"
t  "enumeration-only handle allowed"      check_users
mkproc 4000 python3        "${I915}drm-engine-compute:\t9000 ns\ndrm-total-local0:\t2 GiB\n"
tn "client with work/memory refused"      check_users
reset_proc
mkproc 4001 llama-server   "${I915}drm-total-local0:\t512 MiB\n"
tn "client with memory only refused"      check_users
reset_proc
mkproc 4002 legacy         "pos:\t0\nflags:\t02\n"
tn "no usage stats -> refused"            check_users
reset_proc
mkproc 4003 xeclient       "drm-driver:\txe\ndrm-total-cycles-rcs:\t99999\ndrm-cycles-rcs:\t0\n"
t  "xe: free-running total-cycles ignored" check_users
reset_proc
mkproc 4004 other          "${I915}drm-total-local0:\t2 GiB\n" "" /dev/zero
t  "fd on another device ignored"         check_users
reset_proc
mkproc 4005 container-app  "${I915}drm-total-local0:\t1 GiB\n"
tn "node outside /dev/dri caught by device number" check_users
reset_proc
mkdir -p "$PROC_ROOT/4006"; echo comfyui > "$PROC_ROOT/4006/comm"
printf '7f00-7f10 rw-s 1000 00:05 42 /dev/dri/renderD129\n' > "$PROC_ROOT/4006/maps"
tn "fd closed but buffers mmap'ed refused" check_users
reset_proc
mkdir -p "$PROC_ROOT/4007"
printf '7f00-7f10 rw-s 1000 00:05 42 /dev/dri/renderD128\n' > "$PROC_ROOT/4007/maps"
t  "mmap of another GPU's node ignored"   check_users
reset_proc
mkproc 1577 kwin_wayland   "${I915}drm-engine-render:\t100 ns\n"
sample_wait() { printf '%b' "${I915}drm-engine-render:\t200 ns\n" > "$PROC_ROOT/1577/fdinfo/9"; }
tn "session holder rendering on dGPU refused" check_users
sample_wait() { :; }
reset_proc
mkproc 1577 kwin_wayland   "$I915"
STRICT_IN_USE=1
tn "STRICT_IN_USE=1 refuses any handle"   check_users
STRICT_IN_USE=0
t  "fdinfo_stats units"  [ "$(fdinfo_stats <(printf 'drm-pdev: x\ndrm-total-local0: 1 KiB\ndrm-engine-capacity-rcs: 4\n'))" = "1 0 1024" ]

# --- audio stream guard -----------------------------------------------------
ASOUND_ROOT=$FAKE/asound; DGPU_AUD=daud
mkdir -p "$FAKE/daud/sound/card2" "$ASOUND_ROOT/card2/pcm3p/sub0"
echo "state: RUNNING" > "$ASOUND_ROOT/card2/pcm3p/sub0/status"
t  "running HDMI audio on dGPU detected"  audio_streams
echo "closed" > "$ASOUND_ROOT/card2/pcm3p/sub0/status"
tn "closed HDMI audio not reported"       audio_streams
DGPU_AUD=

# --- persistent state ---------------------------------------------------------
STATE_DIR=$FAKE/state; STATE_FILE=$STATE_DIR/state
t  "no saved state -> none"     [ "$(saved_state)" = none ]
save_state off
t  "save off"                   [ "$(saved_state)" = off ]
save_state on
t  "save on"                    [ "$(saved_state)" = on ]
PERSIST=0 save_state off
t  "PERSIST=0 does not save"    [ "$(saved_state)" = on ]
echo garbage > "$STATE_FILE"
t  "garbage state -> none"      [ "$(saved_state)" = none ]

# --- data files -----------------------------------------------------------
t "service template placeholder" grep -q 'ExecStart=@BINDIR@/arc-dgpu-ctl restore' data/arc-dgpu-ctl.service.in
t "service runs before the display manager" grep -q '^Before=display-manager.service' data/arc-dgpu-ctl.service.in
ids_script=$(sed -n 's/^DG2_IDS="\(.*\)"/\1/p' "$SRC" | tr ' ' '\n' | sort)
ids_udev=$(grep -o '0x56[0-9a-f][0-9a-f]\|0x569[0-9a-f]' data/99-arc-dgpu-ctl.rules | sed 's/0x//' | sort)
t "udev rule IDs == script IDs" [ "$ids_script" = "$ids_udev" ]

echo "# $pass passed, $fail failed"
[[ $fail -eq 0 ]]
