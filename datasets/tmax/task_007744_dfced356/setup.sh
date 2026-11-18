#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cython numpy

    mkdir -p /home/user/pipeline/logs
    mkdir -p /home/user/pipeline/output
    mkdir -p /home/user/pipeline/data

    cat << 'EOF' > /home/user/pipeline/setup.py
from setuptools import setup
from Cython.Build import cythonize
import numpy as np

setup(
    name='fast_agg',
    ext_modules=cythonize("fast_agg.pyx"),
    # MISSING: proper numpy include directory configuration
)
EOF

    cat << 'EOF' > /home/user/pipeline/fast_agg.pyx
import numpy as np
cimport numpy as np

def aggregate_metric(double mean, double variance):
    if variance <= 0.0:
        raise ZeroDivisionError("Variance is zero or negative, cannot aggregate.")
    return mean / np.sqrt(variance)
EOF

    cat << 'EOF' > /home/user/pipeline/processor.py
def compute_stats(values):
    n = len(values)
    if n == 0:
        return 0.0, 0.0

    # Naive precision-loss calculation
    sum_val = sum(values)
    sum_sq = sum(v * v for v in values)

    mean = sum_val / n
    # Catastrophic cancellation happens here for large values with small variance
    variance = (sum_sq / n) - (mean * mean)

    return mean, variance
EOF

    cat << 'EOF' > /home/user/pipeline/run_pipeline.py
import json
import os
from processor import compute_stats
from fast_agg import aggregate_metric

def main():
    # Simulated data triggering the precision bug
    # Base value of 100000000.0, fluctuations of 0.00001
    # Naive variance will become 0.0 due to float64 precision limits
    data = {
        "SEN-1001": [10.1, 10.2, 10.15, 10.25],
        "SEN-8842": [100000000.00001, 100000000.00002, 100000000.00001, 100000000.00003]
    }

    results = {}
    for sensor, values in data.items():
        mean, var = compute_stats(values)
        metric = aggregate_metric(mean, var)
        results[sensor] = metric

    with open('/home/user/pipeline/output/final_metrics.json', 'w') as f:
        json.dump(results, f)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/pipeline/logs/generator.log
[2023-11-01T10:00:00Z] Generated batch for SEN-1001
[2023-11-01T10:00:05Z] Generated batch for SEN-8842
[2023-11-01T10:00:10Z] Generated batch for SEN-9999
EOF

    cat << 'EOF' > /home/user/pipeline/logs/processor.log
1698832801.0 - Processed SEN-1001
1698832806.0 - Processed SEN-8842
1698832811.0 - Processed SEN-9999
EOF

    cat << 'EOF' > /home/user/pipeline/logs/aggregator.log
2023/11/01 10:00:02 INFO Aggregating SEN-1001
2023/11/01 10:00:07 CRITICAL: ZeroDivisionError in fast_agg
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
