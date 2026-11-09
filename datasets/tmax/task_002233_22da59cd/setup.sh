#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    mkdir -p /home/user/workspace
    mkdir -p /home/user/results

    cat << 'EOF' > /home/user/workspace/generate_data.py
import numpy as np

np.random.seed(42)
N = 1000
features = 5

# Train data
X_train = np.random.normal(loc=0.0, scale=1.0, size=(800, features))
y_train = (X_train[:, 0] + X_train[:, 1] > 0).astype(int)

# Test data (different distribution to make the leak impactful)
X_test = np.random.normal(loc=5.0, scale=2.0, size=(200, features))
y_test = (X_test[:, 0] + X_test[:, 1] > 10).astype(int) # shifted threshold

X = np.vstack((X_train, X_test))
y = np.concatenate((y_train, y_test))

with open('/home/user/workspace/dataset.csv', 'w') as f:
    for i in range(N):
        row = ",".join(f"{val:.4f}" for val in X[i])
        f.write(f"{row},{y[i]}\n")
EOF

    python3 /home/user/workspace/generate_data.py

    cat << 'EOF' > /home/user/workspace/knn_pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <time.h>

#define N 1000
#define FEATURES 5
#define K 3
#define TRAIN_RATIO 0.8

float data[N][FEATURES];
int labels[N];

void load_data() {
    FILE *file = fopen("dataset.csv", "r");
    if (!file) {
        printf("Cannot open dataset.csv\n");
        exit(1);
    }
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < FEATURES; j++) {
            fscanf(file, "%f,", &data[i][j]);
        }
        fscanf(file, "%d\n", &labels[i]);
    }
    fclose(file);
}

void normalize_data(int train_size) {
    // BUG: Data leakage! Calculating mean and std over the entire dataset (0 to N)
    // instead of just the training dataset (0 to train_size).
    for (int j = 0; j < FEATURES; j++) {
        float sum = 0;
        for (int i = 0; i < N; i++) {
            sum += data[i][j];
        }
        float mean = sum / N;

        float sq_diff_sum = 0;
        for (int i = 0; i < N; i++) {
            sq_diff_sum += (data[i][j] - mean) * (data[i][j] - mean);
        }
        float std = sqrt(sq_diff_sum / N);
        if (std == 0) std = 1;

        for (int i = 0; i < N; i++) {
            data[i][j] = (data[i][j] - mean) / std;
        }
    }
}

float distance(float *a, float *b) {
    float dist = 0;
    for (int i = 0; i < FEATURES; i++) {
        dist += (a[i] - b[i]) * (a[i] - b[i]);
    }
    return sqrt(dist);
}

int predict(float *query, int train_size) {
    float best_dists[K];
    int best_labels[K];
    for (int i = 0; i < K; i++) best_dists[i] = 1e9;

    for (int i = 0; i < train_size; i++) {
        float d = distance(query, data[i]);
        for (int j = 0; j < K; j++) {
            if (d < best_dists[j]) {
                for (int m = K - 1; m > j; m--) {
                    best_dists[m] = best_dists[m - 1];
                    best_labels[m] = best_labels[m - 1];
                }
                best_dists[j] = d;
                best_labels[j] = labels[i];
                break;
            }
        }
    }

    int count1 = 0;
    for (int i = 0; i < K; i++) {
        if (best_labels[i] == 1) count1++;
    }
    return (count1 > K / 2) ? 1 : 0;
}

int main() {
    load_data();

    int train_size = (int)(N * TRAIN_RATIO);
    int test_size = N - train_size;

    normalize_data(train_size);

    int correct = 0;
    clock_t start = clock();

    for (int i = train_size; i < N; i++) {
        int pred = predict(data[i], train_size);
        if (pred == labels[i]) {
            correct++;
        }
    }

    clock_t end = clock();
    double time_spent = (double)(end - start) / CLOCKS_PER_SEC;

    float accuracy = (float)correct / test_size;
    printf("Test Accuracy: %.4f\n", accuracy);
    printf("Avg Inference Time: %.6f seconds\n", time_spent / test_size);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
