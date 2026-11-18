#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data /home/user/src /home/user/out

    cat << 'EOF' > /home/user/data/embeddings.csv
1.0,2.0,0
2.0,3.0,0
3.0,1.0,1
4.0,5.0,1
5.0,4.0,0
6.0,8.0,1
7.0,6.0,0
8.0,7.0,1
9.0,10.0,0
10.0,9.0,1
EOF

    cat << 'EOF' > /home/user/src/normalize.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NUM_ROWS 10
#define NUM_FEATURES 2
#define TRAIN_ROWS 8

int main() {
    FILE *fp = fopen("/home/user/data/embeddings.csv", "r");
    if (!fp) {
        perror("Failed to open file");
        return 1;
    }

    double data[NUM_ROWS][NUM_FEATURES];
    int labels[NUM_ROWS];
    char line[256];
    int row = 0;

    while (fgets(line, sizeof(line), fp) && row < NUM_ROWS) {
        sscanf(line, "%lf,%lf,%d", &data[row][0], &data[row][1], &labels[row]);
        row++;
    }
    fclose(fp);

    double min[NUM_FEATURES];
    double max[NUM_FEATURES];

    for (int j = 0; j < NUM_FEATURES; j++) {
        min[j] = data[0][j];
        max[j] = data[0][j];
    }

    // BUG: Data leak! Computes min/max over the entire dataset instead of just TRAIN_ROWS.
    for (int i = 0; i < NUM_ROWS; i++) {
        for (int j = 0; j < NUM_FEATURES; j++) {
            if (data[i][j] < min[j]) min[j] = data[i][j];
            if (data[i][j] > max[j]) max[j] = data[i][j];
        }
    }

    FILE *f_train = fopen("/home/user/out/train_scaled.csv", "w");
    FILE *f_test = fopen("/home/user/out/test_scaled.csv", "w");

    for (int i = 0; i < NUM_ROWS; i++) {
        FILE *out = (i < TRAIN_ROWS) ? f_train : f_test;
        for (int j = 0; j < NUM_FEATURES; j++) {
            double scaled = (data[i][j] - min[j]) / (max[j] - min[j]);
            fprintf(out, "%f,", scaled);
        }
        fprintf(out, "%d\n", labels[i]);
    }

    fclose(f_train);
    fclose(f_test);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
