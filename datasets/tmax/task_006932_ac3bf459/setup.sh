#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.txt
10000.1
10000.2
10000.3
10000.4
10000.5
EOF

    cat << 'EOF' > /home/user/sensor_stats.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    FILE *fp = fopen("/home/user/data.txt", "r");
    if (!fp) return 1;

    float val;
    float sum = 0.0f;
    float sum_sq = 0.0f;
    int count = 0;

    while (fscanf(fp, "%f", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        count++;
    }
    fclose(fp);

    float mean = sum / count;
    float variance = (sum_sq / count) - (mean * mean);
    float stddev = sqrtf(variance);

    FILE *out = fopen("/home/user/output.log", "w");
    fprintf(out, "Mean: %.6f\n", mean);
    fprintf(out, "Variance: %.6f\n", variance);
    fprintf(out, "StdDev: %.6f\n", stddev);
    fclose(out);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
