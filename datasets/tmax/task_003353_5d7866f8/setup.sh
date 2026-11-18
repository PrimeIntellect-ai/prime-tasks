#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/ingest.log
[2023-10-01 10:00:01] RequestID: REQ-101 | Mean: 5.2 | Median: 5.1 | Variance: 1.4 | StdDev: 1.18
[2023-10-01 10:00:05] RequestID: REQ-102 | Mean: 3.3 | Median: 3.2 | Variance: 2.1 | StdDev: 1.44
[2023-10-01 10:00:10] RequestID: REQ-103 | Mean: 7.7 | Median: 7.7 | Variance: 0.0 | StdDev: 0.0
[2023-10-01 10:00:15] RequestID: REQ-104 | Mean: 2.1 | Median: 2.0 | Variance: 1.1 | StdDev: 1.04
EOF

    cat << 'EOF' > /home/user/logs/compute.log
[2023-10-01 10:00:02] RequestID: REQ-101 | Started computation
[2023-10-01 10:00:02] RequestID: REQ-101 | Finished computation in 150ms
[2023-10-01 10:00:06] RequestID: REQ-102 | Started computation
[2023-10-01 10:00:06] RequestID: REQ-102 | Finished computation in 145ms
[2023-10-01 10:00:11] RequestID: REQ-103 | Started computation
[2023-10-01 10:00:17] RequestID: REQ-103 | Finished computation in 6000ms
[2023-10-01 10:00:16] RequestID: REQ-104 | Started computation
[2023-10-01 10:00:16] RequestID: REQ-104 | Finished computation in 160ms
EOF

    cat << 'EOF' > /home/user/logs/writer.log
[2023-10-01 10:00:03] RequestID: REQ-101 | Status: SUCCESS
[2023-10-01 10:00:07] RequestID: REQ-102 | Status: SUCCESS
[2023-10-01 10:00:17] RequestID: REQ-103 | Status: TIMEOUT
[2023-10-01 10:00:17] RequestID: REQ-104 | Status: SUCCESS
EOF

    cat << 'EOF' > /home/user/math_compute.py
import time
import math

def calculate_std(data):
    if not data: return 0.0
    mean = sum(data) / len(data)
    variance = sum((x - mean) ** 2 for x in data) / len(data)
    return math.sqrt(variance)

def slow_fallback_compute(data):
    # Simulates an unoptimized path that takes a long time
    time.sleep(6)
    return [0.0] * len(data)

def fast_compute(data, std):
    return [(x - sum(data)/len(data)) / std for x in data]

def normalize_and_compute(data):
    std = calculate_std(data)
    if std == 0.0:
        return slow_fallback_compute(data)
    return fast_compute(data, std)
EOF

    cat << 'EOF' > /home/user/verify.py
import time
import sys
from math_compute import normalize_and_compute

def run_test():
    test_data = [5.0, 5.0, 5.0, 5.0, 5.0]
    start = time.time()
    result = normalize_and_compute(test_data)
    duration = time.time() - start

    if duration > 1.0:
        print("Failed: Computation took too long.")
        sys.exit(1)

    if result != [0.0, 0.0, 0.0, 0.0, 0.0]:
        print("Failed: Incorrect output.")
        sys.exit(1)

    with open("/home/user/success.log", "w") as f:
        f.write("VERIFICATION_PASSED\n")
    print("Success!")

if __name__ == "__main__":
    run_test()
EOF

    chmod +x /home/user/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
