#!/bin/bash

exit 0

# NOTYET, Revist later

# Adds launchers to the xfce panel.
# Approach from:
#   https://forum.xfce.org/viewtopic.php?id=8619

# Run by the panel.desktop item that is placed
# into the .config/autostart directory by the Dockerfile.

if [ ! -e $HOME/.config/xfce4/panel/launcher-50 ];
then
  mkdir -p $HOME/.config/xfce4/panel/launcher-50
  cp /usr/share/applications/mousepad.desktop $HOME/.config/xfce4/panel/launcher-50

  mkdir -p $HOME/.config/xfce4/panel/launcher-52
  cp /usr/share/applications/firefox-esr.desktop $HOME/.config/xfce4/panel/launcher-52

  xfce4-panel -r
  xfconf-query -c xfce4-panel -p /plugins/plugin-50 -t string -s "launcher" --create
  xfconf-query -c xfce4-panel -p /plugins/plugin-50/items -t string -s "mousepad.desktop" -a --create

  xfconf-query -c xfce4-panel -p /plugins/plugin-52 -t string -s "launcher" --create
  xfconf-query -c xfce4-panel -p /plugins/plugin-52/items -t string -s "firefox-esr.desktop" -a --create

  xfconf-query -c xfce4-panel -p /plugins/plugin-53 -t string -s "separator" --create

  xfconf-query -c xfce4-panel -p /panels/panel-2/plugin-ids -rR
  xfconf-query -c xfce4-panel -p /panels/panel-2/plugin-ids -t int -s 15 -t int -s 16 -t int -s 17 -t int -s 50 -t int -s 51 -t int -s 52 -t int -s 53 -t int -s 18 -t int -s 20 -t int -s 21 -t int -s 22 --create

  xfce4-panel -r

  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -n -t bool -s false
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -n -t bool -s false
fi
