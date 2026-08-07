#!/bin/bash

wget -q -O - https://raw.githubusercontent.com/bxGenesis/start/main/raw-bisos.sh |
tee raw-bisos.sh

./raw-bisos.sh -v -n showRun -i installUnsitedBisos
