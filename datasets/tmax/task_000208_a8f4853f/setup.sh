#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest pandas numpy scikit-learn flask fastapi uvicorn joblib

    useradd -m -s /bin/bash user || true

    # Generate dataset
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd
np.random.seed(42)
X = np.random.randn(1000, 15)
# Introduce collinearity
X[:, 6] = X[:, 2] * 0.95 + np.random.randn(1000) * 0.1 # f7 highly correlated with f3
X[:, 11] = X[:, 5] * 0.9 + np.random.randn(1000) * 0.1 # f12 highly correlated with f6
columns = [f'f{i+1}' for i in range(15)]
df = pd.DataFrame(X, columns=columns)
# Target generation
df['target'] = 2.5 * df['f1'] - 1.2 * df['f3'] + 0.8 * df['f8'] + np.random.randn(1000) * 0.5
df.to_csv('/home/user/dataset.csv', index=False)
EOF
    python3 /tmp/gen_data.py

    # Create vendored package
    mkdir -p /app/fast-tracker-1.0/src
    mkdir -p /app/fast-tracker-1.0/fast_tracker

    cat << 'EOF' > /app/fast-tracker-1.0/src/math_utils.c
#include <stdio.h>
void dummy() {
    int unused = 1;
}
EOF

    cat << 'EOF' > /app/fast-tracker-1.0/Makefile
CFLAGS = -O3 -Werror

all:
	gcc $(CFLAGS) -c src/math_utils.c -o src/math_utils.o
EOF

    cat << 'EOF' > /app/fast-tracker-1.0/setup.py
from setuptools import setup
setup(
    name='fast-tracker',
    version='1.0.0',
    packages=['fast_tracker'],
)
EOF

    cat << 'EOF' > /app/fast-tracker-1.0/fast_tracker/__init__.py
_metrics = {}
def log_metric(name, value):
    _metrics[name] = value
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
