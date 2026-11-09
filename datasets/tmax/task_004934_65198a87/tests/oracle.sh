#!/bin/bash
ID="ARCHIVE-77A-XYZ"

if [ ! -f "$1" ]; then
    echo "$ID|INVALID"
    exit 0
fi

len=$(wc -c < "$1")
if [ "$len" -lt 4 ]; then
    echo "$ID|INVALID"
    exit 0
fi

magic=$(head -c 4 "$1" | xxd -p)
if [ "$magic" != "7f454c46" ]; then
    echo "$ID|INVALID"
    exit 0
fi

bytes=$(head -c 16 "$1" | xxd -p | tr -d '\n')
padded=$(printf "%-32s" "$bytes" | tr ' ' '0')
echo "$ID|$padded"
