#!/bin/bash
# verify.sh --- Smoke-test a running privileged systemd container from the host.
#
# Runs a series of `docker exec ... systemctl/journalctl` checks against the
# container and reports PASS/FAIL for each. Also probes the host-exposed ports.
#
# Usage:
#   ./verify.sh                       # uses defaults below
#   ./verify.sh <container> <ssh> <vnc> <novnc>
#
# Exit status is non-zero if any check fails.

set -u

CONTAINER="${1:-mb-deb13-sysd-xfce-1}"
SSH_PORT="${2:-2224}"
VNC_PORT="${3:-5903}"
NOVNC_PORT="${4:-6903}"

SERVICES="vncserver novnc sshd-container"

PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

# check <description> <command...>
# PASS if the command exits 0.
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

dex() { docker exec "$CONTAINER" "$@"; }

echo "== Verifying container: $CONTAINER =="

# 0. Container is actually running.
check "container is running" \
  bash -c "[ \"\$(docker inspect -f '{{.State.Running}}' '$CONTAINER' 2>/dev/null)\" = true ]"

# 1. systemd is PID 1.
check "systemd is PID 1" \
  bash -c "[ \"\$(docker exec '$CONTAINER' cat /proc/1/comm 2>/dev/null)\" = systemd ]"

# 2. Overall system state. `is-system-running` prints running|degraded and
#    exits 0 only for "running". Treat "degraded" as a soft warning below.
sys_state=$(dex systemctl is-system-running 2>/dev/null)
if [ "$sys_state" = running ]; then
  printf '  [%s] system state: running\n' "$(green PASS)"
  PASS=$((PASS + 1))
elif [ "$sys_state" = degraded ]; then
  printf '  [%s] system state: degraded (see --failed below)\n' "$(red FAIL)"
  FAIL=$((FAIL + 1))
  dex systemctl --failed --no-pager --no-legend | sed 's/^/        /'
else
  printf '  [%s] system state: %s\n' "$(red FAIL)" "${sys_state:-unknown}"
  FAIL=$((FAIL + 1))
fi

# 3. Each service is active.
for svc in $SERVICES; do
  check "service active: $svc" dex systemctl is-active --quiet "$svc"
done

# 4. journald is functional (boot log is non-empty).
check "journald has a boot log" \
  bash -c "docker exec '$CONTAINER' journalctl -b -n1 --no-pager >/dev/null 2>&1"

# 5. Host-exposed ports are listening.
for p in "$SSH_PORT:SSH" "$VNC_PORT:VNC" "$NOVNC_PORT:noVNC"; do
  port="${p%%:*}"; name="${p##*:}"
  check "host port listening: $name ($port)" \
    bash -c "ss -ltn 2>/dev/null | grep -q ':$port '"
done

# 6. noVNC web endpoint responds.
check "noVNC HTTP responds (:$NOVNC_PORT)" \
  bash -c "curl -sSf -o /dev/null --max-time 5 http://localhost:$NOVNC_PORT/"

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
