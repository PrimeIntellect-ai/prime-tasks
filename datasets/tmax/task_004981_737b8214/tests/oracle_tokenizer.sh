#!/bin/bash
if [ -z "$1" ]; then
    exit 0
fi

for word in $1; do
    if [ "$word" == "missing" ]; then
        echo "NaN"
    elif [[ "$word" =~ ^[0-9]+$ ]]; then
        echo "${word}.0"
    else
        echo "$word"
    fi
done
