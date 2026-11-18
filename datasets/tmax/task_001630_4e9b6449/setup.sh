#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas scikit-learn numpy

    mkdir -p /app
    mkdir -p /home/user/data

    # Create and compile legacy_scorer
    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    double s1 = atof(argv[1]);
    double s2 = atof(argv[2]);
    double s3 = atof(argv[3]);
    double s4 = atof(argv[4]);

    double score = (s1 * 1.5) + (s2 * s2) - s3 + (s4 * 0.5);
    if (score > 10.0) {
        printf("1\n");
    } else {
        printf("0\n");
    }
    return 0;
}
EOF
    gcc -O2 /tmp/scorer.c -o /app/legacy_scorer
    strip /app/legacy_scorer
    rm /tmp/scorer.c

    # Generate datasets
    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 5000
ids = np.arange(1, n + 1)
s1 = np.random.normal(0, 2, n)
s2 = np.random.normal(2, 1, n)
s3 = np.random.normal(-1, 3, n)
s4 = np.random.normal(5, 2, n)

# Outliers in s3
outlier_indices = np.random.choice(n, 50, replace=False)
s3[outlier_indices] = np.random.uniform(10000, 20000, 50)

# NaNs
for s in [s1, s2, s3, s4]:
    nan_indices = np.random.choice(n, 200, replace=False)
    s[nan_indices] = np.nan

df_a = pd.DataFrame({'id': ids, 'sensor1': s1, 'sensor2': s2})
df_b = pd.DataFrame({'id': ids, 'sensor3': s3, 'sensor4': s4})

df_a.to_csv('/home/user/data/sensors_a.csv', index=False)
df_b.to_csv('/home/user/data/sensors_b.csv', index=False)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create baseline.py
    cat << 'EOF' > /home/user/baseline.py
import pandas as pd
import subprocess
from sklearn.impute import SimpleImputer
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier

df_a = pd.read_csv('/home/user/data/sensors_a.csv')
df_b = pd.read_csv('/home/user/data/sensors_b.csv')
df = df_a.merge(df_b, on='id')

# Data Leakage: Imputing on the whole dataset before splitting
imputer = SimpleImputer(strategy='mean')
features = ['sensor1', 'sensor2', 'sensor3', 'sensor4']
df[features] = imputer.fit_transform(df[features])

# (Skipping label generation for baseline brevity)
print("Baseline script with data leakage.")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
