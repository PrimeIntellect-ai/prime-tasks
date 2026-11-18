#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
f1,f2
10.0,20.0
12.0,22.0
14.0,24.0
16.0,26.0
18.0,28.0
EOF

    cat << 'EOF' > /home/user/process.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

#define N 5

uint32_t state = 42;
uint32_t xorshift32() {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

int main() {
    double data[N][2];
    FILE *f = fopen("/home/user/data.csv", "r");
    char buffer[100];
    fgets(buffer, 100, f); // skip header
    for(int i=0; i<N; i++) {
        fscanf(f, "%lf,%lf", &data[i][0], &data[i][1]);
    }
    fclose(f);

    // BUG: Calculating stats on the whole dataset
    double mean[2] = {0}, std[2] = {0};
    for(int j=0; j<2; j++) {
        for(int i=0; i<N; i++) mean[j] += data[i][j];
        mean[j] /= N;
        for(int i=0; i<N; i++) std[j] += (data[i][j] - mean[j]) * (data[i][j] - mean[j]);
        std[j] = sqrt(std[j] / N);
    }

    int train_indices[N];
    int oob[N];
    for(int i=0; i<N; i++) oob[i] = 1;

    for(int i=0; i<N; i++) {
        train_indices[i] = xorshift32() % N;
        oob[train_indices[i]] = 0;
    }

    FILE *f_train = fopen("/home/user/train_scaled.csv", "w");
    fprintf(f_train, "f1,f2\n");
    for(int i=0; i<N; i++) {
        int idx = train_indices[i];
        fprintf(f_train, "%.4f,%.4f\n", 
                (data[idx][0] - mean[0]) / std[0], 
                (data[idx][1] - mean[1]) / std[1]);
    }
    fclose(f_train);

    FILE *f_test = fopen("/home/user/test_scaled.csv", "w");
    fprintf(f_test, "f1,f2\n");
    for(int i=0; i<N; i++) {
        if(oob[i]) {
            fprintf(f_test, "%.4f,%.4f\n", 
                    (data[i][0] - mean[0]) / std[0], 
                    (data[i][1] - mean[1]) / std[1]);
        }
    }
    fclose(f_test);

    FILE *f_stats = fopen("/home/user/stats.txt", "w");
    fprintf(f_stats, "f1: mean=%.4f, std=%.4f\n", mean[0], std[0]);
    fprintf(f_stats, "f2: mean=%.4f, std=%.4f\n", mean[1], std[1]);
    fclose(f_stats);

    return 0;
}
EOF

    chmod -R 777 /home/user
