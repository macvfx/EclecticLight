#!/bin/zsh
cd "$(dirname "$0")"
echo "Eclectic Light Updater"
echo "======================"
echo
./eclectic-updater.py check
echo
echo "To update out-of-date apps:              ./eclectic-updater.py update"
echo "To flatten apps and collect ReadMe files:  ./eclectic-updater.py organize"
echo "To install Installomator first:          ./eclectic-updater.py --install-installomator"
echo
echo "Press any key to close this window..."
read -k1
