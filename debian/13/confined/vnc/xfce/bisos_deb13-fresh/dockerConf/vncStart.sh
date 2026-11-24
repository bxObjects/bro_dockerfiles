#!/bin/bash
#
# vncStart.sh --- Start the TigerVNC server: with no password (the default), or with the
# VNC password kept in the host's leaf directory.
#
# Installed in the confined image at /usr/local/bin/vncStart.sh and inherited by the sysd
# images. Called by the confined entrypoint.sh and by the sysd images' vncserver.service, as
# the desktop user (bystar).
#
# The password lives on the HOST, in the leaf directory: <leaf>/bisosVncPasswd, in the
# format of "vncpasswd -f", mode 0600, git-ignored. Every leaf bind-mounts its directory at
# /shuttle/this, so it survives delete, re-create and image rebuilds. It is written by
# "containerManage.sh vncPassword set|clear" (bro_dockerfiles) or
# "containerProc_instanceVncPassword set|clear" (bisos.dockerProc). So:
#   host file missing or empty  -> no password (-SecurityTypes None)
#   host file non-empty         -> VNC password (-SecurityTypes VncAuth -rfbauth <copy>)
# It is read at each VNC start: a change takes effect when the container (re)starts.
#
# The host file belongs to the host user, not to bystar, so it is copied through
# passwordless sudo to /run/bisosVncPasswd (bystar's, mode 0600). /run is a tmpfs in the
# sysd containers: the copy is never in the container's writable layer or in a committed
# snapshot. noVNC (websockify) needs no change: it prompts whenever the VNC server asks.
#
# Usage: vncStart.sh [display] [vncserver options...]
#   e.g. vncStart.sh :1 -localhost no -geometry 1920x1080 -depth 16

hostPasswdFile="/shuttle/this/bisosVncPasswd"
runPasswdFile="/run/bisosVncPasswd"

sudo -n rm -f "$runPasswdFile"
if sudo -n test -s "$hostPasswdFile"; then
  if sudo -n install -m 600 -o "$(id -u)" -g "$(id -g)" "$hostPasswdFile" "$runPasswdFile"; then
    echo "vncStart.sh: VNC auth: password (from $hostPasswdFile)"
    exec /usr/bin/vncserver "$@" -SecurityTypes VncAuth -rfbauth "$runPasswdFile"
  fi
  # A password was asked for but cannot be used: refuse rather than fall back to none.
  echo "vncStart.sh: ERROR: cannot copy $hostPasswdFile to $runPasswdFile; VNC not started." >&2
  exit 1
fi
echo "vncStart.sh: VNC auth: none"
exec /usr/bin/vncserver "$@" -SecurityTypes None --I-KNOW-THIS-IS-INSECURE
