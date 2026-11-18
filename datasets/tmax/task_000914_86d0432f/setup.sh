#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > stats.py
import math

class StreamingStats:
    def __init__(self):
        self.sum = 0.0
        self.sum_sq = 0.0
        self.count = 0

    def update(self, x):
        self.sum += x
        self.sum_sq += x * x
        self.count += 1

    def get_stddev(self):
        if self.count < 2:
            return 0.0
        mean = self.sum / self.count
        # BUG: Catastrophic cancellation when variance is near zero and values are large
        variance = (self.sum_sq - self.count * mean * mean) / (self.count - 1)
        return math.sqrt(variance)
EOF

    cat << 'EOF' > process.py
import csv
from stats import StreamingStats

def main():
    stats = StreamingStats()
    with open('/home/user/sensor_data.csv', 'r') as f:
        reader = csv.reader(f)
        next(reader) # skip header
        for i, row in enumerate(reader):
            val = float(row[1])
            stats.update(val)
            if stats.count >= 2:
                stddev = stats.get_stddev()
                print(f"Row {i+1}: val={val}, stddev={stddev:.4f}")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > sensor_data.csv
timestamp,value
1600000000,10.1
1600000001,10.2
1600000002,10.1
1600000003,100000000.1
1600000004,100000000.1
1600000005,100000000.1
1600000006,100000000.2
1600000007,100000000.1
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
