#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Move existing .termux directory and create a symlink
mv ~/.termux ~/.termux.bak
ln -s ~/everest/.termux ~/.termux

# @TODO: Complete the installation process
