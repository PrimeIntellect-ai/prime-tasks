#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("ERROR: INVALID FORMAT");
        return 1;
    }

    char service_name[256];
    char port_str[256], uid_str[256], storage_str[256];
    char extra[256];

    int parsed = sscanf(argv[1], "%255s %255s %255s %255s %255s", service_name, port_str, uid_str, storage_str, extra);
    if (parsed != 4) {
        printf("ERROR: INVALID FORMAT");
        return 1;
    }

    char *endptr;
    long port = strtol(port_str, &endptr, 10);
    if (*endptr != '\0') { printf("ERROR: INVALID FORMAT"); return 1; }

    long uid = strtol(uid_str, &endptr, 10);
    if (*endptr != '\0') { printf("ERROR: INVALID FORMAT"); return 1; }

    long storage = strtol(storage_str, &endptr, 10);
    if (*endptr != '\0') { printf("ERROR: INVALID FORMAT"); return 1; }

    long net3 = port % 256;
    long net4 = uid % 256;
    long quota = (storage * 2) + 128;

    printf("[%s]\nPortMap: 80->%ld\nNetwork: 172.18.%ld.%ld/24\nStorage_Quota: %ldM", service_name, port, net3, net4, quota);

    return 0;
}
EOF

    gcc -O2 /tmp/legacy.c -o /app/legacy_net_quota.bin
    strip /app/legacy_net_quota.bin
    chmod +x /app/legacy_net_quota.bin
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
