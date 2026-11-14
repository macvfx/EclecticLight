#!/bin/zsh
cd "$(dirname "$0")"
echo "Eclectic Light Updater (zsh)"
echo "=============================="
echo
./eclectic-updater.zsh check
echo
echo "To update out-of-date apps:                    ./eclectic-updater.zsh update"
echo "To flatten apps and collect ReadMe files:  ./eclectic-updater.zsh organize"
echo "To install Installomator first:                ./eclectic-updater.zsh --install-installomator"
echo
echo "Press any key to close this window..."
read -k1
