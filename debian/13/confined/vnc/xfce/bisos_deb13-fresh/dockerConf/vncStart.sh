#!/bin/bash
#
# vncStart.sh --- Start the TigerVNC server: with no password (the default), or with the
# instance's VNC password if one has been set.
#
# Installed in the confined image at /usr/local/bin/vncStart.sh and inherited by the sysd
# images. Called by the confined entrypoint.sh and by the sysd images' vncserver.service, as
# the desktop user (bystar).
#
# The password file is /home/bystar/.config/bisosVncPasswd, in the format of "vncpasswd -f".
# It is put there by "containerManage.sh vncPassword set" (bro_dockerfiles) or
# "containerProc_instanceVncPassword set" (bisos.dockerProc), with docker/podman cp, so it
# arrives owned by root: it is made bystar's (mode 0600) here, through passwordless sudo.
# "vncPassword clear" copies in an empty file. So:
#   file missing or empty  -> no password (-SecurityTypes None)
#   file non-empty         -> VNC password (-SecurityTypes VncAuth -rfbauth <file>)
# noVNC (websockify) needs no change: it prompts whenever the VNC server asks for a password.
#
# Usage: vncStart.sh [display] [vncserver options...]
#   e.g. vncStart.sh :1 -localhost no -geometry 1920x1080 -depth 16

passwdFile="$HOME/.config/bisosVncPasswd"

if [ -e "$passwdFile" ] && [ ! -O "$passwdFile" ]; then
  sudo -n chown "$(id -u):$(id -g)" "$passwdFile" && sudo -n chmod 600 "$passwdFile"
fi

if [ -s "$passwdFile" ]; then
  echo "vncStart.sh: VNC auth: password ($passwdFile)"
  exec /usr/bin/vncserver "$@" -SecurityTypes VncAuth -rfbauth "$passwdFile"
else
  echo "vncStart.sh: VNC auth: none"
  exec /usr/bin/vncserver "$@" -SecurityTypes None --I-KNOW-THIS-IS-INSECURE
fi
