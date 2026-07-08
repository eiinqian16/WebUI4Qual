#!/bin/sh

echo "Content-Type: text/plain"
echo ""

logread | tail -n 500