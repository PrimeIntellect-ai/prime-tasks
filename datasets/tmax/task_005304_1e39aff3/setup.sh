#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/id_mapper.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    long long raw_id;
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, "%lld", &raw_id) == 1) {
            long long canonical = (raw_id ^ 0xDEADBEEF) % 99991;
            if (canonical < 0) canonical = -canonical;
            printf("%lld\n", canonical);
            fflush(stdout);
        }
    }
    return 0;
}
EOF
    gcc -O3 -s /tmp/id_mapper.c -o /app/id_mapper
    chmod +x /app/id_mapper
    rm /tmp/id_mapper.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline
    chmod -R 777 /home/user
