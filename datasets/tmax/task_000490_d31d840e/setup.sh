#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/net_health_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "ERROR: File not found\n");
        return 1;
    }
    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        fprintf(stderr, "ERROR: File not found\n");
        return 1;
    }

    int total = 0;
    int success = 0;
    int timeout = 0;
    char line[1024];

    while (fgets(line, sizeof(line), fp)) {
        total++;
        char ts[256], ip[256], port[256], status[256];
        if (sscanf(line, "[%255[^]]] %255s %255s %255s", ts, ip, port, status) == 4) {
            if (strcmp(status, "SUCCESS") == 0) {
                success++;
            } else if (strcmp(status, "TIMEOUT") == 0) {
                timeout++;
            }
        }
    }
    fclose(fp);

    int score = 0;
    if (total > 0) {
        score = (success * 100) / total;
    }

    printf("Total: %d\n", total);
    printf("Success: %d\n", success);
    printf("Timeout: %d\n", timeout);
    printf("Health Score: %d%%\n", score);

    return 0;
}
EOF

    gcc /tmp/net_health_checker.c -o /app/net_health_checker
    strip /app/net_health_checker
    rm /tmp/net_health_checker.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logrotate.d
    mkdir -p /var/log

    chmod -R 777 /home/user
