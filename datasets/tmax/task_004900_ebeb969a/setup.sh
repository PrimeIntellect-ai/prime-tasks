#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

# Setup git config
git config --global init.defaultBranch main
git config --global user.email "test@example.com"
git config --global user.name "Test User"

mkdir -p /home/user/sensor_project/src
mkdir -p /home/user/sensor_project/tests
cd /home/user/sensor_project
git init

# Create initial files
cat << 'EOF' > src/math_utils.py
def apply_calibration(reading):
    # Apply standard sensor calibration multiplier
    return reading * 1.00023
EOF

cat << 'EOF' > src/pipeline.py
from src.math_utils import apply_calibration

def process_batch(batch):
    calibrated = [apply_calibration(r) for r in batch]
    return sum(calibrated)
EOF

cat << 'EOF' > tests/test_pipeline.py
import pytest
import random
from src.pipeline import process_batch

def test_aggregation_precision():
    # Random data can mask or exacerbate precision loss
    # With a large batch, precision loss accumulates and fails
    random.seed()
    batch = [random.uniform(50.0, 150.0) for _ in range(5000)]

    # Expected: sum of batch * 1.00023
    expected = sum(batch) * 1.00023
    actual = process_batch(batch)

    # Assert tolerance
    assert abs(actual - expected) < 1e-5, f"Precision loss detected: {actual} != {expected}"
EOF

git add .
git commit -m "Initial commit with good precision"

# Create 50 good commits
for i in $(seq 1 50); do
    echo "# dummy line $i" >> src/pipeline.py
    git commit -am "Dummy commit $i"
done

git tag v1.0

# Create more good commits
for i in $(seq 51 120); do
    echo "# dummy line $i" >> src/pipeline.py
    git commit -am "Dummy commit $i"
done

# INTRODUCE THE BUG (Commit ~121)
cat << 'EOF' > src/math_utils.py
def apply_calibration(reading):
    # Apply standard sensor calibration multiplier
    # Rounding to 2 decimal places to save memory / bandwidth
    return float(f"{reading * 1.00023:.2f}")
EOF
git commit -am "Introduce calibration rounding for bandwidth optimization"

# Create 80 more dummy commits
for i in $(seq 121 200); do
    echo "# post bug dummy line $i" >> src/pipeline.py
    git commit -am "Post-bug dummy commit $i"
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
