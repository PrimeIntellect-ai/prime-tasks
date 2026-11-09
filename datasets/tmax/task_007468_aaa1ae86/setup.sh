#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential gawk
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    # Generate data.csv: values 1.0 to 1000.0
    awk 'BEGIN {for(i=1;i<=1000;i++) printf("%.1f\n", i)}' > data.csv

    # Create buggy normalize.c
    cat << 'EOF' > normalize.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <sys/time.h>

#define TOTAL_ROWS 1000

int main() {
    FILE *fp = fopen("data.csv", "r");
    if (!fp) return 1;

    float data[TOTAL_ROWS];
    for(int i=0; i<TOTAL_ROWS; i++) {
        fscanf(fp, "%f", &data[i]);
    }
    fclose(fp);

    // BUG: Using all data for stats
    double sum = 0;
    for(int i=0; i<TOTAL_ROWS; i++) sum += data[i];
    double mean = sum / TOTAL_ROWS;

    double sq_sum = 0;
    for(int i=0; i<TOTAL_ROWS; i++) sq_sum += (data[i] - mean) * (data[i] - mean);
    double std = sqrt(sq_sum / TOTAL_ROWS);

    // Normalize everything
    FILE *out = fopen("normalized_all.csv", "w");
    for(int i=0; i<TOTAL_ROWS; i++) {
        fprintf(out, "%.4f\n", (data[i] - mean) / std);
    }
    fclose(out);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
