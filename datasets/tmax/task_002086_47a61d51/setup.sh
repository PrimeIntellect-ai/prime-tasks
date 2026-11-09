#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk bc sed
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /app
    cat << 'EOF' > /app/model.c
#include <stdio.h>

int main() {
    int f1, f2, f3, f4;
    while (scanf("%d,%d,%d,%d", &f1, &f2, &f3, &f4) == 4) {
        float prediction = (f1 * 2) + (f2 * 3) - f3 + f4;
        printf("%.2f\n", prediction);
    }
    return 0;
}
EOF
    gcc -O2 /app/model.c -o /app/model_predictor
    strip /app/model_predictor
    rm /app/model.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)

def generate_dataset(n_rows, features_file, labels_file):
    X = np.random.randint(0, 100, size=(n_rows, 4)).astype(float)

    # Introduce missing values
    mask = np.random.rand(n_rows, 4) < 0.1
    X_missing = X.copy()
    X_missing[mask] = np.nan

    # Calculate column means ignoring nans
    means = np.round(np.nanmean(X_missing, axis=0)).astype(int)

    # Calculate labels using imputed values
    X_imputed = X_missing.copy()
    for j in range(4):
        X_imputed[np.isnan(X_imputed[:, j]), j] = means[j]

    labels = (X_imputed[:, 0] * 2) + (X_imputed[:, 1] * 3) - X_imputed[:, 2] + X_imputed[:, 3]

    df_features = pd.DataFrame(X_missing).astype("Int64")
    df_features.to_csv(features_file, index=False, header=False, na_rep='')
    pd.DataFrame(labels).to_csv(labels_file, index=False, header=False)

generate_dataset(1000, '/home/user/data/train_features.csv', '/home/user/data/train_labels.csv')
generate_dataset(500, '/home/user/data/hidden_test_features.csv', '/home/user/data/hidden_test_labels.csv')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
