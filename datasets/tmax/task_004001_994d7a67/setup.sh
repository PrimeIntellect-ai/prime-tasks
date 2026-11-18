#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace ltrace curl
    pip3 install pytest

    mkdir -p /app/bin

    cat << 'EOF' > /tmp/stat_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[256];
    double sum = 0;
    double sum_sq = 0;
    int count = 0;

    while (fgets(buffer, sizeof(buffer), stdin)) {
        if (strstr(buffer, "\x1B\x5B\x44") != NULL) {
            // Infinite loop to simulate deadlock
            while(1) {}
        }
        double val = atof(buffer);
        sum += val;
        sum_sq += val * val;
        count++;
    }

    if (count > 0) {
        double mean = sum / count;
        // Simple population variance calculation
        double variance = (sum_sq / count) - (mean * mean);
        // Correcting for floating point inaccuracies if variance is very close to 0
        if (variance < 0) variance = 0;
        printf("Mean: %.3f, Variance: %.3f\n", mean, variance);
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/bin/stat_analyzer /tmp/stat_analyzer.c
    rm /tmp/stat_analyzer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
