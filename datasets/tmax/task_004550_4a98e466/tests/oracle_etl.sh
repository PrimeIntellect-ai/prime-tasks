#!/bin/bash
awk -F'|' -v OFS='|' '
{
    epoch = $1; event = $2; plate = $3; speed = $4;

    # Check deduplication window
    key = event "|" plate;
    is_dup = 0;
    if (key in last_seen) {
        diff = epoch - last_seen[key];
        # strictly within 3000ms inclusive -> if diff <= 3000 and diff >= -3000
        # Assuming stream is mostly chronological but absolute diff is safer
        if ((diff >= -3000 && diff <= 3000)) {
            is_dup = 1;
        }
    }

    if (!is_dup) {
        last_seen[key] = epoch;

        # Masking
        if (plate ~ /^[A-Z][A-Z][A-Z][0-9][0-9][0-9]$/) {
            plate = "***" substr(plate, 4, 3);
        }

        # Normalization
        sec = int(epoch / 1000);
        cmd = "date -u -d @" sec " +%Y-%m-%dT%H:%M:%SZ";
        cmd | getline iso_date;
        close(cmd);

        print iso_date, event, plate, speed;
    }
}'
