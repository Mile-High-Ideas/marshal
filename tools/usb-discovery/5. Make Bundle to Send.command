#!/bin/bash
# Double-click this file LAST, after you've run the other steps. It packages all
# the results into a single file for you to send back to Brandon.
cd "$(dirname "$0")" || exit 1
chmod +x ./scan.sh 2>/dev/null
./scan.sh --bundle
echo
echo "==> A file named  marshal-discovery-<date>.tar.gz  is now in this folder."
echo "    Send that ONE file back to Brandon (drag it into Messages or email)."
printf "Press Return to close... "
read -r _
