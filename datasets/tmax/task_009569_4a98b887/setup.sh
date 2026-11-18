#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Generate dataset
np.random.seed(42)
X = np.random.normal(10, 5, 100)
y = 3.5 * X + np.random.normal(0, 2, 100)

# Introduce missing values in X (-999.0)
missing_indices = np.random.choice(100, 10, replace=False)
X[missing_indices] = -999.0

with open('/home/user/data.csv', 'w') as f:
    for i in range(100):
        f.write(f"{X[i]},{y[i]}\n")

# Generate buggy C code
buggy_c_code = """#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define N 100
#define TRAIN_SIZE 80
#define TEST_SIZE 20

void calc_stats(float *X, int n, float *mean, float *std) {
    float sum = 0.0;
    int count = 0;
    for (int i = 0; i < n; i++) {
        if (X[i] != -999.0) {
            sum += X[i];
            count++;
        }
    }
    *mean = sum / count;

    float var_sum = 0.0;
    for (int i = 0; i < n; i++) {
        if (X[i] != -999.0) {
            var_sum += (X[i] - *mean) * (X[i] - *mean);
        }
    }
    *std = sqrt(var_sum / count);
}

void impute_and_normalize(float *X, int n, float mean, float std) {
    for (int i = 0; i < n; i++) {
        if (X[i] == -999.0) {
            X[i] = mean;
        }
        X[i] = (X[i] - mean) / std;
    }
}

float fit_regression(float *X, float *y, int n, float *bias) {
    float sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
    for (int i = 0; i < n; i++) {
        sum_x += X[i];
        sum_y += y[i];
        sum_xy += X[i] * y[i];
        sum_xx += X[i] * X[i];
    }
    float weight = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x);
    *bias = (sum_y - weight * sum_x) / n;
    return weight;
}

float evaluate(float weight, float bias, float *X, float *y, int n) {
    float mse = 0.0;
    for (int i = 0; i < n; i++) {
        float pred = weight * X[i] + bias;
        mse += (pred - y[i]) * (pred - y[i]);
    }
    return mse / n;
}

int main() {
    float X[N], y[N];
    FILE *f = fopen("/home/user/data.csv", "r");
    for (int i = 0; i < N; i++) {
        fscanf(f, "%f,%f", &X[i], &y[i]);
    }
    fclose(f);

    // BUG: Data leakage! Calculating stats and normalizing over the entire dataset before splitting.
    float global_mean, global_std;
    calc_stats(X, N, &global_mean, &global_std);
    impute_and_normalize(X, N, global_mean, global_std);

    float X_train[TRAIN_SIZE], y_train[TRAIN_SIZE];
    float X_test[TEST_SIZE], y_test[TEST_SIZE];

    for (int i = 0; i < TRAIN_SIZE; i++) {
        X_train[i] = X[i];
        y_train[i] = y[i];
    }
    for (int i = 0; i < TEST_SIZE; i++) {
        X_test[i] = X[TRAIN_SIZE + i];
        y_test[i] = y[TRAIN_SIZE + i];
    }

    float bias;
    float weight = fit_regression(X_train, y_train, TRAIN_SIZE, &bias);
    float mse = evaluate(weight, bias, X_test, y_test, TEST_SIZE);

    printf("%f\\n", mse);
    return 0;
}
"""

with open('/home/user/pipeline.c', 'w') as f:
    f.write(buggy_c_code)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
