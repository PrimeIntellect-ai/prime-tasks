#!/bin/bash
# Oracle implementation for fuzzing
HEADER_HEX=$(head -c 8 "$1")
HEADER_LEN=$((16#$HEADER_HEX))
SKIP_BYTES=$((9 + HEADER_LEN))
tail -c +$((SKIP_BYTES + 1)) "$1" > /tmp/payload.gz
gzip -d -c /tmp/payload.gz > /tmp/extracted.log
awk -v sev="[$2]" '
    /^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
        if (match_found && buffer != "") {
            print buffer "\n"
        }
        if (index($0, sev) > 0) {
            match_found = 1
            buffer = $0
        } else {
            match_found = 0
            buffer = ""
        }
        next
    }
    {
        if (match_found) {
            buffer = buffer "\n" $0
        }
    }
    END {
        if (match_found && buffer != "") {
            print buffer "\n"
        }
    }
' /tmp/extracted.log | sed '/^$/N;/^\n$/D' | sed '$d'
