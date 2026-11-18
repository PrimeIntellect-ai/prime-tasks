#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/transactions

    cat << 'EOF' > /home/user/aggregate_transactions.py
import sys
import math
import os

def calculate_std_dev(values):
    n = len(values)
    if n < 2: return 0.0
    sum_x = sum(values)
    sum_x2 = sum(x**2 for x in values)
    # Naive formula prone to catastrophic cancellation
    variance = (sum_x2 - (sum_x**2) / n) / (n - 1)
    return math.sqrt(variance)

def process_dir(directory):
    results = []
    for f in sorted(os.listdir(directory)):
        if f.endswith('.csv'):
            with open(os.path.join(directory, f)) as file:
                values = [float(line.strip()) for line in file if line.strip()]
                std_dev = calculate_std_dev(values)
                results.append(f"{f},{std_dev:.4f}")
    return results

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python aggregate_transactions.py <directory>")
        sys.exit(1)
    res = process_dir(sys.argv[1])
    for r in res:
        print(r)
EOF

    cat << 'EOF' > /home/user/transactions/batch_1.csv
10.0
12.0
14.0
16.0
18.0
EOF

    cat << 'EOF' > /home/user/transactions/batch_2.csv
1000000001.0
1000000002.0
1000000003.0
1000000004.0
1000000005.0
EOF

    cat << 'EOF' > /home/user/transactions/batch_3.csv
100000000.1
100000000.2
100000000.15
100000000.1
100000000.2
EOF

    cat << 'EOF' > /home/user/container_logs.txt
[INFO] Starting batch processing job...
[INFO] Processing batch_1.csv...
[INFO] Processing batch_2.csv...
[WARN] Possible precision degradation detected in memory block.
[INFO] Processing batch_3.csv...
Traceback (most recent call last):
  File "/home/user/aggregate_transactions.py", line 28, in <module>
    res = process_dir(sys.argv[1])
  File "/home/user/aggregate_transactions.py", line 20, in process_dir
    std_dev = calculate_std_dev(values)
  File "/home/user/aggregate_transactions.py", line 12, in calculate_std_dev
    return math.sqrt(variance)
ValueError: math domain error
[ERROR] Container crashed with exit code 1.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
