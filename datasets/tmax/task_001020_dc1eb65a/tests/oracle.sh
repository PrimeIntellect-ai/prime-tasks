#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
    # Regex to match exactly MAGIC|SIZE|DATA where SIZE is digits
    if [[ "$line" =~ ^([^|]+)\|([0-9]+)\|(.*)$ ]]; then
        magic="${BASH_REMATCH[1]}"
        size="${BASH_REMATCH[2]}"
        data="${BASH_REMATCH[3]}"

        if [ "$magic" == "BKP7" ] && [ "${#data}" -eq "$size" ]; then
            echo "OK: $data"
        else
            echo "ERR: $line"
        fi
    else
        echo "ERR: $line"
    fi
done
