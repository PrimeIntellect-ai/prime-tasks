#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/stats_service.py
import sys

class StatsTracker:
    def __init__(self):
        self.data = []

    def add_point(self, x):
        self.data.append(x)

    def get_variance(self):
        n = len(self.data)
        if n < 2:
            return 0.0
        sum_x = sum(self.data)
        sum_sq = sum(x**2 for x in self.data)
        mean = sum_x / n
        # Naive formula, susceptible to catastrophic cancellation
        variance = (sum_sq - n * (mean**2)) / (n - 1)
        return variance

def main():
    tracker = StatsTracker()
    with open('/home/user/data.txt', 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                val = float(line)
                tracker.add_point(val)

    with open('/home/user/output.txt', 'w') as f:
        f.write(f"{tracker.get_variance():.6f}\n")

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /tmp/generate_data.py
import random
random.seed(42)
with open('/home/user/data.txt', 'w') as f:
    for _ in range(1000000):
        f.write(f"{1000000000.0 + random.uniform(0, 10)}\n")
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
