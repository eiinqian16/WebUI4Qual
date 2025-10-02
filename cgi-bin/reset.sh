#!/bin/sh

echo "Content-Type: text/plain"
echo ""
echo "Reset script triggered."

# Wipe overlay data manually
rm -rf /overlay/*

# Reboot to apply reset
reboot