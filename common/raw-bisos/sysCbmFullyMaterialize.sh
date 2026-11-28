#!/bin/bash

# Fully materialize this system's CBMs: runs the one copy for every platform,
#     /bisos/core/raw/bin/sysCbmFullyMaterialize.sh   (bisos/raw, on PATH once raw-bisos.sh has run)
# which logs to ~/sysCbmFullyMaterialize-<yymmddHHMMSS>-log.org and exits with sysCbmManage.cs's code.
#
# Run as bystar, AFTER installRawBisos.sh and a container down+up (so the groups
# created by installRawBisos.sh take effect):
#     cd ~/raw-bisos && bash sysCbmFullyMaterialize.sh

shared=/bisos/core/raw/bin/sysCbmFullyMaterialize.sh

if [ ! -x "${shared}" ] ; then
    echo "sysCbmFullyMaterialize: ${shared} is missing --- has raw-bisos.sh run, and is bisos/raw current?" 1>&2
    exit 1
fi

exec "${shared}" "$@"
