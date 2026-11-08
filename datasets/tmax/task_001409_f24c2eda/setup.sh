#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tzdata libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/proxy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main() {
    char buffer[1024];
    FILE *f = fopen("/home/user/metrics_data/metrics.log", "a");
    if (!f) return 1;

    while (fgets(buffer, sizeof(buffer), stdin)) {
        if (strstr(buffer, "ERROR")) {
            // BUG: silently drops errors
            continue;
        }
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        char time_str[64];
        // DO NOT change this format string
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S %Z", t);
        fprintf(f, "[%s] %s", time_str, buffer);
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/test_metrics.txt
INFO CPU usage is at 45%
ERROR Memory leak detected in worker process
WARN Latency spiked to 200ms
EOF

    chmod -R 777 /home/user
