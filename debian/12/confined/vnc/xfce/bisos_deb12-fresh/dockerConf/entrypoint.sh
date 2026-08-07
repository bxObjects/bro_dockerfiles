#!/bin/bash

echo "Running: /usr/sbin/sshd -D &"
sudo /usr/sbin/sshd -D &

# Cleanup from past vnc session that may hav been running in the container.
# This clean-up is not done when the container is stopped (not deleted).
rm /tmp/.X11-unix/X1
rm /tmp/.X1-lock

# Launch the VNC server
vncserver \
  -localhost no \
  -geometry 1920x1080 \
  -depth 16 \
  -SecurityTypes None --I-KNOW-THIS-IS-INSECURE

# Launch the noVNC server.
websockify -D --web=/usr/share/novnc 6901 localhost:5901 &

echo HOME=$HOME

# This allows images that use this as a base
# to insert a script that will run on startup.
if [ -f $HOME/dockerConf/launch.bash ] ; then
  echo "Running $HOME/dockerConf/launch.sh"
  source $HOME/dockerConf/launch.sh
fi

if [ -d /shuttle/this/raw-bisos ] ; then
  ln -s /shuttle/this/raw-bisos $HOME/raw-bisos
fi

# NOTYET::  This is a user wide boot time activity

# # Do some git configuration so that the user doesn't have to.
# RUN git config --global credential.helper store \
#  && git config --global merge.conflictstyle diff3 \
#  && git config --global merge.tool vscode \
#  && git config --global mergetool.keepBackup false \
#  && git config --global core.editor "emacs" \
#  && git config --global pull.ff only \
#  && git config --global init.defaultBranch main \
#  && git config --global safe.directory '*' \
#  && echo "" >> .bashrc \
#  && echo "source /usr/share/bash-completion/completions/git" >> .bashrc



sleep infinity
