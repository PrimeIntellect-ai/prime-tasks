#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app/db

    # Create old naive implementation
    cat << 'EOF' > /home/user/sensor_calc_old.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Count: 0\nMean: 0.000000\nVariance: 0.000000\n");
        return 0;
    }
    int count = argc - 1;
    double sum = 0.0;
    double sum_sq = 0.0;
    for (int i = 1; i < argc; i++) {
        double val = atof(argv[i]);
        sum += val;
        sum_sq += val * val;
    }
    double mean = sum / count;
    double variance = 0.0;
    if (count > 1) {
        variance = (sum_sq - (sum * sum) / count) / (count - 1);
    }
    printf("Count: %d\nMean: %.6f\nVariance: %.6f\n", count, mean, variance);
    return 0;
}
EOF

    # Create oracle implementation
    cat << 'EOF' > /tmp/sensor_calc_oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Count: 0\nMean: 0.000000\nVariance: 0.000000\n");
        return 0;
    }
    int count = 0;
    double mean = 0.0;
    double M2 = 0.0;
    for (int i = 1; i < argc; i++) {
        double val = atof(argv[i]);
        count++;
        double delta = val - mean;
        mean += delta / count;
        double delta2 = val - mean;
        M2 += delta * delta2;
    }
    double variance = 0.0;
    if (count > 1) {
        variance = M2 / (count - 1);
    }
    printf("Count: %d\nMean: %.6f\nVariance: %.6f\n", count, mean, variance);
    return 0;
}
EOF

    gcc -O2 /tmp/sensor_calc_oracle.c -o /app/sensor_calc_oracle
    strip /app/sensor_calc_oracle
    rm /tmp/sensor_calc_oracle.c

    # Create dummy WAL file
    cat << 'EOF' > /app/db/metrics.db-wal
100000000.1
100000000.2
100000000.3
100000000.4
100000000.5
100000000.6
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
