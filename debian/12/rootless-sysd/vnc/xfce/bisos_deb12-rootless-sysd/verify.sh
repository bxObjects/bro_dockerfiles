#!/bin/bash
# verify.sh --- Smoke-test a running rootless-sysd container from the host.
#
# Same checks as the privileged variant's verify.sh, but driven through
# `podman exec` and with an extra assertion that the container is genuinely
# ROOTLESS (container UID 0 maps to a non-root host UID).
#
# Usage:
#   ./verify.sh                       # uses defaults below
#   ./verify.sh <container> <ssh> <vnc> <novnc>
#
# Exit status is non-zero if any check fails.

set -u

CONTAINER="${1:-bisos-deb12-rootless-sysd}"
SSH_PORT="${2:-2225}"
VNC_PORT="${3:-5904}"
NOVNC_PORT="${4:-6904}"

SERVICES="vncserver novnc sshd-container"

PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

check() {
  local desc="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    printf '  [%s] %s\n' "$(green PASS)" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  [%s] %s\n' "$(red FAIL)" "$desc"
    printf '        %s\n' "${out:-<no output>}"
    FAIL=$((FAIL + 1))
  fi
}

pex() { podman exec "$CONTAINER" "$@"; }

echo "== Verifying rootless container: $CONTAINER =="

# 0. Container is running.
check "container is running" \
  bash -c "[ \"\$(podman inspect -f '{{.State.Running}}' '$CONTAINER' 2>/dev/null)\" = true ]"

# 1. systemd is PID 1.
check "systemd is PID 1" \
  bash -c "[ \"\$(podman exec '$CONTAINER' cat /proc/1/comm 2>/dev/null)\" = systemd ]"

# 2. Genuinely rootless: container UID 0 must NOT be host UID 0.
check "container is rootless (root maps to non-root host UID)" \
  bash -c "[ \"\$(podman inspect -f '{{.HostConfig.Privileged}}' '$CONTAINER' 2>/dev/null)\" = false ] && [ \"\$(id -u)\" != 0 ]"

# 3. Overall system state.
sys_state=$(pex systemctl is-system-running 2>/dev/null)
if [ "$sys_state" = running ]; then
  printf '  [%s] system state: running\n' "$(green PASS)"
  PASS=$((PASS + 1))
elif [ "$sys_state" = degraded ]; then
  printf '  [%s] system state: degraded (see --failed below)\n' "$(red FAIL)"
  FAIL=$((FAIL + 1))
  pex systemctl --failed --no-pager --no-legend | sed 's/^/        /'
else
  printf '  [%s] system state: %s\n' "$(red FAIL)" "${sys_state:-unknown}"
  FAIL=$((FAIL + 1))
fi

# 4. Each service is active.
for svc in $SERVICES; do
  check "service active: $svc" pex systemctl is-active --quiet "$svc"
done

# 5. journald is functional.
check "journald has a boot log" \
  bash -c "podman exec '$CONTAINER' journalctl -b -n1 --no-pager >/dev/null 2>&1"

# 6. Host-exposed ports are listening.
for p in "$SSH_PORT:SSH" "$VNC_PORT:VNC" "$NOVNC_PORT:noVNC"; do
  port="${p%%:*}"; name="${p##*:}"
  check "host port listening: $name ($port)" \
    bash -c "ss -ltn 2>/dev/null | grep -q ':$port '"
done

# 7. noVNC web endpoint responds.
check "noVNC HTTP responds (:$NOVNC_PORT)" \
  bash -c "curl -sSf -o /dev/null --max-time 5 http://localhost:$NOVNC_PORT/"

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
