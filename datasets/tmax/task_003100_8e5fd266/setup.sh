#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy setuptools

    mkdir -p /app/data_purify/data_purify
    mkdir -p /verifier

    cat << 'EOF' > /app/data_purify/setup.py
from setuptools import setup, find_packages
setup(name='data_purify', version='0.1.0', packages=find_packages())
EOF

    touch /app/data_purify/data_purify/__init__.py

    cat << 'EOF' > /app/data_purify/data_purify/cleaner.py
def filter_valid(records):
    # BUG: The 'and False' causes all records to be dropped.
    return [r for r in records if r.get('category') != 'unknown' and False]
EOF

    cat << 'EOF' > /verifier/oracle.py
import sys
import json
import numpy as np

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("0.0000")
        return

    valid_data = [r for r in data if r.get('category') != 'unknown']
    if len(valid_data) < 2:
        print("0.0000")
        return

    x = np.array([r['x'] for r in valid_data], dtype=float)
    y = np.array([r['y'] for r in valid_data], dtype=float)

    var_x = np.var(x)
    var_y = np.var(y)

    if var_x == 0 or var_y == 0:
        print("0.0000")
        return

    cov_xy = np.cov(x, y, bias=True)[0, 1]
    pearson = cov_xy / np.sqrt(var_x * var_y)

    if pearson > 0.5:
        m = cov_xy / var_x
        c = np.mean(y) - m * np.mean(x)
        pred = m * 100.0 + c
        print(f"{pred:.4f}")
    else:
        print("0.0000")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
