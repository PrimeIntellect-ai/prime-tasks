#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import random
random.seed(42)
with open("/home/user/response_times.txt", "w") as f:
    for _ in range(100000):
        # Mean 1000000, Stddev 2.5
        val = random.gauss(1000000, 2.5)
        f.write(f"{val:.6f}\n")
EOF
    python3 /tmp/gen_data.py

    cat << 'EOF' > /home/user/uptime_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <assert.h>

int main() {
    FILE *f = fopen("/home/user/response_times.txt", "r");
    if (!f) {
        perror("Failed to open file");
        return 1;
    }

    double val;
    double sum = 0.0;
    double sum_sq = 0.0;
    int n = 0;

    // Naive one-pass calculation - numerically unstable for large means
    while (fscanf(f, "%lf", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        n++;
    }
    fclose(f);

    double variance = (sum_sq - (sum * sum) / n) / n;

    double stddev = sqrt(variance);
    // Catastrophic cancellation makes variance negative, resulting in NaN stddev
    assert(!isnan(stddev));

    printf("Count: %d, Mean: %.2f, StdDev: %.2f\n", n, sum/n, stddev);
    return 0;
}
EOF

    chmod -R 777 /home/user
