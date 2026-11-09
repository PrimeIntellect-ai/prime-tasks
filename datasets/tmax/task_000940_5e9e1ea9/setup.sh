#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user
cd /home/user

# Generate raw_data.csv deterministically
echo "f1,f2,f3,target" > raw_data.csv
for i in $(seq 1 150); do
  if [ $((i % 15)) -eq 0 ]; then
    echo "NA,$((i*2)),$((i*3)),0" >> raw_data.csv
  else
    echo "$((i+1)),$((i*2)),$((i*3)),$((i*4))" >> raw_data.csv
  fi
done

# Create the buggy pipeline.c
cat << 'EOF' > pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#define MAX_ROWS 500
#define FEATURES 3

void read_csv(const char* filename, double data[][FEATURES], int* rows) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        printf("Error opening %s\n", filename);
        exit(1);
    }
    char line[1024];
    *rows = 0;
    while (fgets(line, sizeof(line), file)) {
        double f1, f2, f3, target;
        if (sscanf(line, "%lf,%lf,%lf,%lf", &f1, &f2, &f3, &target) == 4) {
            data[*rows][0] = f1;
            data[*rows][1] = f2;
            data[*rows][2] = f3;
            (*rows)++;
        }
    }
    fclose(file);
}

int main() {
    double train_data[MAX_ROWS][FEATURES];
    double test_data[MAX_ROWS][FEATURES];
    int train_rows = 0, test_rows = 0;

    read_csv("train.csv", train_data, &train_rows);
    read_csv("test.csv", test_data, &test_rows);

    double mean[FEATURES] = {0};
    double std[FEATURES] = {0};

    // BUG: Computing stats on BOTH train and test sets
    int total_rows = train_rows + test_rows;

    // Calculate Mean
    for (int i = 0; i < train_rows; i++) {
        for (int j = 0; j < FEATURES; j++) mean[j] += train_data[i][j];
    }
    for (int i = 0; i < test_rows; i++) {
        for (int j = 0; j < FEATURES; j++) mean[j] += test_data[i][j];
    }
    for (int j = 0; j < FEATURES; j++) mean[j] /= total_rows;

    // Calculate Std
    for (int i = 0; i < train_rows; i++) {
        for (int j = 0; j < FEATURES; j++) std[j] += pow(train_data[i][j] - mean[j], 2);
    }
    for (int i = 0; i < test_rows; i++) {
        for (int j = 0; j < FEATURES; j++) std[j] += pow(test_data[i][j] - mean[j], 2);
    }
    for (int j = 0; j < FEATURES; j++) {
        std[j] = sqrt(std[j] / total_rows);
        if (std[j] == 0) std[j] = 1.0;
    }

    // Apply normalization and weights to TEST set
    double weights[FEATURES] = {0.5, -1.2, 0.8};
    double bias = 2.0;

    for (int i = 0; i < test_rows; i++) {
        double prediction = bias;
        for (int j = 0; j < FEATURES; j++) {
            double normalized_val = (test_data[i][j] - mean[j]) / std[j];
            prediction += normalized_val * weights[j];
        }
        printf("%.4f\n", prediction);
    }

    return 0;
}
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
