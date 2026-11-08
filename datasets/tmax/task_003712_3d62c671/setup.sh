#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        char ts[64], sensor[64];
        float val;
        if (sscanf(line, "%[^,],%[^,],%f", ts, sensor, &val) == 3) {
            int score = (val > 50.0) ? 1 : 0;
            printf("%s,%s,%d\n", ts, sensor, score);
            fflush(stdout);
        }
    }
    return 0;
}
EOF

    gcc /app/legacy_scorer.c -o /app/legacy_scorer
    strip /app/legacy_scorer
    rm /app/legacy_scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
