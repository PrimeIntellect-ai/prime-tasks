#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/data.csv
id,feature,label
0,2.0,0
1,2.5,0
2,3.0,0
3,8.0,1
4,8.5,1
5,9.0,1
6,2.2,-1
7,8.8,-1
8,5.0,-1
9,5.6,-1
EOF

    cat << 'EOF' > /home/user/pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define TOTAL_SIZE 10
#define TRAIN_SIZE 6
#define TEST_SIZE 4

typedef struct {
    int id;
    double feature;
    int label;
    double z_score;
} Record;

int main() {
    Record data[TOTAL_SIZE];
    FILE *fp = fopen("/home/user/data.csv", "r");
    if (!fp) return 1;

    char buffer[1024];
    fgets(buffer, 1024, fp); // skip header
    for (int i = 0; i < TOTAL_SIZE; i++) {
        fscanf(fp, "%d,%lf,%d", &data[i].id, &data[i].feature, &data[i].label);
    }
    fclose(fp);

    // --- BUGGY ETL PIPELINE: DATA LEAKAGE ---
    // Calculates mean and stddev using the whole dataset

    double sum = 0;
    for (int i = 0; i < TOTAL_SIZE; i++) {
        sum += data[i].feature;
    }
    double mean = sum / TOTAL_SIZE;

    double sum_sq = 0;
    for (int i = 0; i < TOTAL_SIZE; i++) {
        sum_sq += (data[i].feature - mean) * (data[i].feature - mean);
    }
    double stddev = sqrt(sum_sq / TOTAL_SIZE);

    // Apply normalization to all data
    for (int i = 0; i < TOTAL_SIZE; i++) {
        data[i].z_score = (data[i].feature - mean) / stddev;
    }

    // --- NAIVE BAYES CLASSIFIER ---
    // Train on TRAIN_SIZE
    double sum_0 = 0, sum_sq_0 = 0; int count_0 = 0;
    double sum_1 = 0, sum_sq_1 = 0; int count_1 = 0;
    for (int i = 0; i < TRAIN_SIZE; i++) {
        if (data[i].label == 0) {
            sum_0 += data[i].z_score; count_0++;
        } else {
            sum_1 += data[i].z_score; count_1++;
        }
    }
    double mu_0 = sum_0 / count_0;
    double var_0 = 0;
    for (int i = 0; i < TRAIN_SIZE; i++) {
        if (data[i].label == 0) var_0 += pow(data[i].z_score - mu_0, 2);
    }
    var_0 /= count_0;

    double mu_1 = sum_1 / count_1;
    double var_1 = 0;
    for (int i = 0; i < TRAIN_SIZE; i++) {
        if (data[i].label == 1) var_1 += pow(data[i].z_score - mu_1, 2);
    }
    var_1 /= count_1;

    // Predict on TEST_SIZE
    FILE *out = fopen("predictions.csv", "w");
    fprintf(out, "id,z_score,predicted_label\n");
    for (int i = TRAIN_SIZE; i < TOTAL_SIZE; i++) {
        double x = data[i].z_score;
        double p0 = exp(-pow(x - mu_0, 2) / (2 * var_0)) / sqrt(2 * M_PI * var_0);
        double p1 = exp(-pow(x - mu_1, 2) / (2 * var_1)) / sqrt(2 * M_PI * var_1);
        int pred = (p1 > p0) ? 1 : 0;
        fprintf(out, "%d,%.6f,%d\n", data[i].id, data[i].z_score, pred);
    }
    fclose(out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
