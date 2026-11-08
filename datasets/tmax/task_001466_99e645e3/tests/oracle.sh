#!/bin/bash
state=1000
salt=8392
while read -r action value checksum; do
    if [ -z "$action" ]; then continue; fi
    expected_checksum=$(( (value * salt) % 9973 ))
    if [ "$checksum" -eq "$expected_checksum" ]; then
        if [ "$action" == "ADD" ]; then
            state=$((state + value))
        elif [ "$action" == "SUB" ]; then
            state=$((state - value))
        elif [ "$action" == "MUL" ]; then
            state=$((state * value))
        fi
    fi
done < "$1"
echo "$state"
