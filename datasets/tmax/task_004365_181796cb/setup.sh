#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gcc
    pip3 install pytest

    mkdir -p /home/user/data
    cd /home/user/data

    # Create sensors.csv (id: 1 to 100, val1: id * 2.0)
    for i in $(seq 1 100); do
        echo "$i,$(echo "$i * 2.0" | bc -l)" >> sensors.csv
    done

    # Create labels.csv (id: 1 to 100, label: id % 2)
    for i in $(seq 1 100); do
        echo "$i,$((i % 2))" >> labels.csv
    done

    # Create buggy normalize.c
    cat << 'EOF' > /home/user/normalize.c
#include <stdio.h>
#include <stdlib.h>

#define MAX_ROWS 1000

int main() {
    FILE *fp = fopen("/home/user/data/joined.csv", "r");
    if (!fp) {
        printf("Error opening joined.csv\n");
        return 1;
    }

    double val1[MAX_ROWS];
    int id[MAX_ROWS];
    int label[MAX_ROWS];
    int count = 0;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%d,%lf,%d", &id[count], &val1[count], &label[count]) == 3) {
            count++;
        }
    }
    fclose(fp);

    // BUG: Data leak. Computing mean over ALL data instead of just the first 80 rows.
    double sum = 0;
    for (int i = 0; i < count; i++) {
        sum += val1[i];
    }
    double mean = sum / count;

    // Output normalized data
    FILE *out = fopen("/home/user/predictions.csv", "w");
    for (int i = 0; i < count; i++) {
        fprintf(out, "%d,%.4f,%d\n", id[i], val1[i] - mean, label[i]);
    }
    fclose(out);

    FILE *log = fopen("/home/user/mean_used.txt", "w");
    fprintf(log, "%.4f\n", mean);
    fclose(log);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
