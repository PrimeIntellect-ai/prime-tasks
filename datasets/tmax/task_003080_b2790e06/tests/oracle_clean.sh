#!/bin/bash
awk -F',' '
BEGIN { OFS="," }
$3 != "TEST_EVENT" {
    # Normalize
    $3 = toupper($3)
    $4 = sprintf("%.2f", $4)

    # Deduplicate: Keep max timestamp, tie-break by latest in stream
    if (!($2 in max_ts) || $1 >= max_ts[$2]) {
        max_ts[$2] = $1
        record[$2] = $2 "," $1 "," $3 "," $4
    }
}
END {
    for (u in record) {
        print record[u]
    }
}' | sort -t',' -k1,1
