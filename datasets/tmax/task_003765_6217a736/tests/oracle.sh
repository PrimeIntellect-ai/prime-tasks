#!/bin/bash
in_file=0
reject=0
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "BEGIN FILE: "* ]]; then
        in_file=1
        filepath="${line#BEGIN FILE: }"
        if [[ "$filepath" == *".."* ]]; then
            reject=1
            echo "REJECTED: $filepath"
        else
            reject=0
            sanitized="${filepath//\//_}"
            sanitized="${sanitized//\\/_}"
            echo "ACCEPTED: $sanitized"
        fi
    elif [[ "$line" == "END FILE" ]]; then
        if [ "$in_file" -eq 1 ] && [ "$reject" -eq 0 ]; then
            echo "END ACCEPTED"
        fi
        in_file=0
        reject=0
    else
        if [ "$in_file" -eq 1 ] && [ "$reject" -eq 0 ]; then
            echo "$line" | tr '[:lower:]' '[:upper:]'
        fi
    fi
done
