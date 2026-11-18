#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/requirements.txt
scipy==1.10.1
numpy==1.20.0
EOF

    cat << 'EOF' > /home/user/app/stats_calculator.py
import concurrent.futures
import math
import sys

class StatTracker:
    def __init__(self):
        self.sum_x = 0.0
        self.sum_x2 = 0.0
        self.count = 0

    def add_batch(self, batch):
        local_sum = sum(batch)
        local_sum2 = sum(x*x for x in batch)
        local_count = len(batch)

        # Race condition here
        self.sum_x += local_sum
        self.sum_x2 += local_sum2
        self.count += local_count

def process_data():
    tracker = StatTracker()
    data = [[10.0]*1000 for _ in range(200)]

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        executor.map(tracker.add_batch, data)

    mean = tracker.sum_x / tracker.count
    variance = (tracker.sum_x2 / tracker.count) - (mean * mean)

    try:
        stddev = math.sqrt(variance)
        print(f"Stddev: {stddev}")
    except ValueError as e:
        print("Numerical Instability Detected: math domain error", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    process_data()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
