#!/bin/bash
# Double-click this file in Finder. It opens the Terminal app and runs this
# step for you automatically — just follow the on-screen prompts.
#
# IMPORTANT: the SW4 wheel only shows up when it is POWERED. Have it connected
# to the car with the ignition/accessory ON (or on a 12V bench harness) before
# you plug its USB into the Mac.
cd "$(dirname "$0")" || exit 1
chmod +x ./scan.sh 2>/dev/null
./scan.sh aim-sw4
echo
echo "==> This step is done. You can close this window."
printf "Press Return to close... "
read -r _
