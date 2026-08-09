#!/bin/bash
# run.bash --- Launch the rootless-sysd container under rootless Podman.
#
# Contrast with the privileged variant's docker-compose.yml: there is NO
# --privileged, NO host /sys/fs/cgroup bind mount, NO cgroupns=host.
# `--systemd=always` tells Podman to do the systemd plumbing itself
# (cgroup subtree delegation + tmpfs on /run /run/lock /tmp), all inside
# the launching user's namespace.
#
# Prerequisites (per host, one-time):
#   - podman installed
#   - cgroups v2 with delegation for the user session:
#       stat -fc %T /sys/fs/cgroup            -> cgroup2fs
#       cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers
#         should list: cpu io memory pids
#   - crun as the OCI runtime (podman info | grep -i ociruntime)
#
# Usage: ./run.bash            # start detached
#        ./run.bash --rm       # stop and remove the container

set -u

IMAGE="bisos/deb13-rootless-sysd-vnc-xfce:1"
NAME="bisos-deb13-rootless-sysd"

# Host port assignments for the rootless-sysd deb13 variant.
SSH_PORT=2226
VNC_PORT=5905
NOVNC_PORT=6905

if [ "${1:-}" = "--rm" ]; then
  podman rm -f "$NAME"
  exit $?
fi

podman run -d \
  --name "$NAME" \
  --systemd=always \
  --stop-signal SIGRTMIN+3 \
  -p "${SSH_PORT}:22" \
  -p "${VNC_PORT}:5901" \
  -p "${NOVNC_PORT}:6901" \
  -v "$(pwd):/shuttle/this" \
  "$IMAGE"

echo
echo "Started $NAME"
echo "  SSH   : ssh -p $SSH_PORT <user>@localhost"
echo "  VNC   : localhost:$VNC_PORT"
echo "  noVNC : http://localhost:$NOVNC_PORT"
