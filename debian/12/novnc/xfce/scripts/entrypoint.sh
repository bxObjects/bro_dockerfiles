#!/bin/bash
# set -e: exit asap if a command exits with a non-zero status
# set -e
#
trap ctrl_c INT
function ctrl_c() {
  exit 0
}
# entrypoint.sh file for starting the xvfb with better screen resolution, configuring and running the vnc server.
rm /tmp/.X1-lock 2> /dev/null &
rm ~/.Xauthority ~/.Xauthority-n
xauth generate $DISPLAY . trusted
# /opt/noVNC/utils/launch.sh --vnc localhost:$VNC_PORT --listen $NO_VNC_PORT &

echo DEBUG: Before running  vncserver
ls -l /home/dockeruser/.Xauthority
ls -l /home/dockeruser
id

echo XAUTHORITY=$XAUTHORITY
# Insecure option is needed to accept connections from the docker host.
vncserver $DISPLAY -depth $VNC_COL_DEPTH -geometry $VNC_RESOLUTION -SecurityTypes None -localhost no --I-KNOW-THIS-IS-INSECURE
websockify -D --web=/usr/share/novnc $NO_VNC_PORT localhost:$VNC_PORT
sudo /usr/sbin/sshd -D
wait
