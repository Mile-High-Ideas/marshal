#!/bin/bash
# Double-click this file in Finder. It opens the Terminal app and runs this
# step for you automatically — just follow the on-screen prompts.
cd "$(dirname "$0")" || exit 1
chmod +x ./scan.sh 2>/dev/null
./scan.sh ethernet-adapter
echo
echo "==> This step is done. You can close this window."
printf "Press Return to close... "
read -r _
