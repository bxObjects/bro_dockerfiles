#!/bin/bash

# Fully materialize this system's CBMs (Capability Bundle Materializations):
#     sysCbmManage.cs -i fullyMaterialize
#
# Run as bystar, AFTER installRawBisos.sh and a container down+up (so the groups
# created by installRawBisos.sh take effect):
#     cd ~/raw-bisos && bash sysCbmFullyMaterialize.sh
#
# bystar's ~/.bashrc returns early for non-interactive shells (the standard
# Debian 'case $- in *i*)' guard), before it sets PATH (pipx / bisos3 bin) and
# nvm. Force an interactive shell so sysCbmManage.cs (and node via nvm)
# resolve. Without a tty, -i prints harmless "no job control" warnings.
#
# As raw-bisos.sh does, all output (stdout and stderr) also goes to a log in ~:
#     ~/sysCbmFullyMaterialize-<yymmddHHMMSS>-log.org

localName="sysCbmFullyMaterialize"   # scripts name sans .sh
dateTag=$( date +%y%m%d%H%M%S )
logFile=~/${localName}-${dateTag}-log.org

exec &> >(tee "${logFile}")

echo "${localName}: logging to ${logFile}"

bash -ic 'sysCbmManage.cs -i fullyMaterialize'
exitCode=$?

echo "${localName}: exit ${exitCode}; log: ${logFile}"
exit ${exitCode}
