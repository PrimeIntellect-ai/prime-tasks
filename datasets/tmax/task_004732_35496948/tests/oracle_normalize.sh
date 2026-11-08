#!/bin/bash
export TZ=UTC
awk -F' \\| ' '
BEGIN { OFS="," }
{
    if (NF != 4) next;
    timestamp = $1
    service = $2
    operation = $3
    config_pair = $4

    if (operation != "CREATE" && operation != "MODIFY" && operation != "DELETE") next;

    split(config_pair, kv, "=")
    key = kv[1]
    value = kv[2]
    for (i=3; i<=length(kv); i++) {
        value = value "=" kv[i]
    }

    if (tolower(key) ~ /secret/) next;

    cmd = "date -d \"" timestamp "\" +%s"
    cmd | getline epoch
    close(cmd)

    print epoch, service, operation, key, length(value)
}' | sort -t, -k1,1n -k2,2
