#!/bin/bash

DEVICE="/dev/ttyAML6"
TIMEOUT=3

# http://localhost:8081/node/ext-address
# http://localhost:8081/node/coprocessor/version

if [ -e "$DEVICE" ] && timeout $TIMEOUT dd if="$DEVICE" bs=1 count=1 of=/dev/null 2>/dev/null; then
    exit 0
else
    exit 1
fi
