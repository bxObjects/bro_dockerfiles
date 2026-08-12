#!/bin/bash
# verify.sh --- Smoke-test a running rootless-sysd container (exec-free).
#
# On older Podman (e.g. 4.3.1), `podman exec` into a rootless systemd container
# fails with a nested cgroup.procs permission error --- yet the container runs
# fine and is reachable over SSH. So this script verifies WITHOUT exec:
#   - host-side:  podman inspect (running/rootless), ports, noVNC HTTP
#   - inside:     an SSH session for systemd + service state
# SSH is how these containers are used anyway.
#
# SSH auth: uses sshpass with the default password if sshpass is installed;
# otherwise tries key-based BatchMode SSH. If neither works, the inside-systemd
# checks are reported WARN with a manual command (host-side checks still run).
#
# "degraded" system state is treated as WARN, not FAIL: a container can be
# degraded for irrelevant reasons (e.g. polkit) while our services are healthy.
# The gate is that vncserver/novnc/sshd-container are active.
#
# Usage:
#   ./verify.sh
#   ./verify.sh <container> <ssh> <vnc> <novnc> <user> <password>
#
# Exit status is non-zero if any check fails.

set -u

CONTAINER="${1:-bisos_deb13-rootless-sysd}"
SSH_PORT="${2:-2226}"
VNC_PORT="${3:-5905}"
NOVNC_PORT="${4:-6905}"
SSH_USER="${5:-bystar}"
SSH_PASS="${6:-insecure}"

SERVICES="vncserver novnc sshd-container"

PASS=0; FAIL=0; WARN=0
green(){ printf '\033[32m%s\033[0m' "$1"; }
red(){   printf '\033[31m%s\033[0m' "$1"; }
yellow(){ printf '\033[33m%s\033[0m' "$1"; }
ok(){   printf '  [%s] %s\n' "$(green PASS)" "$1"; PASS=$((PASS+1)); }
bad(){  printf '  [%s] %s\n' "$(red FAIL)" "$1";  FAIL=$((FAIL+1)); }
warn(){ printf '  [%s] %s\n' "$(yellow WARN)" "$1"; WARN=$((WARN+1)); }
check(){ local d="$1"; shift; local out
  if out=$("$@" 2>&1); then ok "$d"; else bad "$d"; printf '        %s\n' "${out:-<no output>}"; fi; }

# SSH runner: sshpass if available, else key-based BatchMode (no hang on prompt).
SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
if command -v sshpass >/dev/null 2>&1; then
  ssh_run(){ sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@localhost" "$@"; }
  SSH_MODE="sshpass"
else
  ssh_run(){ ssh -o BatchMode=yes $SSH_OPTS "$SSH_USER@localhost" "$@"; }
  SSH_MODE="key/BatchMode"
fi

echo "== Verifying rootless container: $CONTAINER (exec-free) =="

# --- host-side (no exec, no ssh) ---
check "container is running" \
  bash -c "[ \"\$(podman inspect -f '{{.State.Running}}' '$CONTAINER' 2>/dev/null)\" = true ]"

check "container is rootless (not privileged, non-root host UID)" \
  bash -c "[ \"\$(podman inspect -f '{{.HostConfig.Privileged}}' '$CONTAINER' 2>/dev/null)\" = false ] && [ \"\$(id -u)\" != 0 ]"

for p in "$SSH_PORT:SSH" "$VNC_PORT:VNC" "$NOVNC_PORT:noVNC"; do
  port="${p%%:*}"; name="${p##*:}"
  check "host port listening: $name ($port)" \
    bash -c "ss -ltn 2>/dev/null | grep -q ':$port '"
done

check "noVNC HTTP responds (:$NOVNC_PORT)" \
  bash -c "curl -sSf -o /dev/null --max-time 5 http://localhost:$NOVNC_PORT/"

# --- inside via SSH ---
if ssh_run true >/dev/null 2>&1; then
  ok "SSH login works ($SSH_MODE, $SSH_USER@localhost:$SSH_PORT)"

  PID1=$(ssh_run 'cat /proc/1/comm' 2>/dev/null)
  if [ "$PID1" = systemd ]; then ok "systemd is PID 1"
  else bad "PID 1 is '${PID1:-unknown}', expected systemd"; fi

  for svc in $SERVICES; do
    if ssh_run "systemctl is-active --quiet $svc" 2>/dev/null; then
      ok "service active: $svc"
    else
      bad "service not active: $svc"
    fi
  done

  STATE=$(ssh_run 'systemctl is-system-running' 2>/dev/null)
  if [ "$STATE" = running ]; then
    ok "system state: running"
  else
    warn "system state: ${STATE:-unknown} (non-fatal if our services are active); failed units:"
    ssh_run 'systemctl --failed --no-legend' 2>/dev/null | sed 's/^/        /'
  fi
else
  warn "SSH not automatable in $SSH_MODE mode (install sshpass, or set up a key)."
  warn "Verify inside manually:"
  warn "  ssh -p $SSH_PORT $SSH_USER@localhost 'systemctl is-system-running; systemctl --failed'"
fi

echo "== $PASS passed, $WARN warnings, $FAIL failed =="
[ "$FAIL" -eq 0 ]
