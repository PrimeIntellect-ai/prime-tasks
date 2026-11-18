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
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        return 1;
    }
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') {
            continue;
        }
        char ip[64];
        int p1, p2;
        if (sscanf(line, "ALLOW %63s %d-%d", ip, &p1, &p2) == 3) {
            printf("iptables -A INPUT -s %s -p tcp --match multiport --dports %d:%d -j ACCEPT\n", ip, p1, p2);
        } else if (sscanf(line, "BLOCK %63s %d", ip, &p1) == 2) {
            printf("iptables -A INPUT -s %s -p tcp --dport %d -j DROP\n", ip, p1);
        }
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /tmp/legacy.c -o /app/legacy_config_gen
    strip /app/legacy_config_gen
    chmod +x /app/legacy_config_gen
    rm /tmp/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
