#!/bin/bash
export LC_ALL=C
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\ (.*)$ ]]; then
        ts="${BASH_REMATCH[1]}"
        msg="${BASH_REMATCH[2]}"

        # Check if date is valid and get epoch
        epoch=$(date -d "$ts" +%s 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Bucket size is 20m = 1200 seconds
            bucket=$(( epoch / 1200 * 1200 ))

            # Clean message: convert encoding, strip non-alnum/spaces, uppercase, squeeze spaces
            clean_msg=$(printf "%s" "$msg" | iconv -f WINDOWS-1252 -t UTF-8 -c 2>/dev/null | tr -cd 'a-zA-Z0-9 ' | tr 'a-z' 'A-Z' | tr -s ' ')

            echo "${bucket}|${clean_msg}"
        fi
    fi
done
