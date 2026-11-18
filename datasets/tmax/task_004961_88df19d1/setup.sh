#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/processor.py
import math

def compute_statistics(data):
    n = len(data)
    if n == 0:
        return 0.0, 0.0
    sum_val = sum(data)
    sum_sq = sum(x**2 for x in data)
    mean = sum_val / n
    # Prone to catastrophic cancellation when variance is near zero and values are large
    variance = (sum_sq - (sum_val**2) / n) / n
    stddev = math.sqrt(variance)
    return mean, stddev
EOF

    cat << 'EOF' > /home/user/app/runner.py
import random
from processor import compute_statistics

def run():
    random.seed(42)
    for _ in range(1000):
        base = random.choice([1.0, 10.0, 100000000.0])
        data = [base + random.uniform(0, 0.000001) for _ in range(10)]
        mean, stddev = compute_statistics(data)
    print("Runner completed successfully.")

if __name__ == "__main__":
    run()
EOF

    cat << 'EOF' > /home/user/app/verify.py
from processor import compute_statistics
import traceback

def verify():
    # This specifically triggers the negative variance issue in the buggy implementation
    data = [100000000.0, 100000000.0, 100000000.0]
    try:
        m, s = compute_statistics(data)
        if s >= 0 and m == 100000000.0:
            with open("/home/user/app/success.log", "w") as f:
                f.write(f"Fixed: {m}, {s}\n")
            print("Verification successful.")
        else:
            print("Verification failed: incorrect math.")
    except Exception as e:
        print("Verification failed: Still crashing")
        traceback.print_exc()

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
