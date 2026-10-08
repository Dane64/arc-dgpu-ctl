# Security policy

arc-dgpu-ctl runs as root and writes to `/sys/bus/pci`. In scope: code
execution via config or environment by a non-root user, unsafe runtime files,
and the udev rule affecting devices it should not.

Only the latest release receives fixes.

Report privately via **Security → Report a vulnerability**
(https://github.com/Dane64/arc-dgpu-ctl/security/advisories/new), not as a
public issue.
