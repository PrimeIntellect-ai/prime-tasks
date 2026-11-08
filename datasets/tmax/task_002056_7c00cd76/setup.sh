#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/logs/api.log
[2023-10-24 10:00:01] [INFO] REQ-101: Received parameters start=1.0, lr=0.1
[2023-10-24 10:00:03] [INFO] REQ-102: Received parameters start=1.5, lr=0.05
[2023-10-24 10:00:05] [INFO] REQ-103: Received parameters start=2.0, lr=1.5
[2023-10-24 10:00:08] [INFO] REQ-104: Received parameters start=0.5, lr=0.01
EOF

    cat << 'EOF' > /home/user/logs/worker.log
[2023-10-24 10:00:01] [INFO] Processing REQ-101...
[2023-10-24 10:00:01] [INFO] REQ-101 finished. Memory: 45MB
[2023-10-24 10:00:03] [INFO] Processing REQ-102...
[2023-10-24 10:00:03] [INFO] REQ-102 finished. Memory: 46MB
[2023-10-24 10:00:05] [INFO] Processing REQ-103...
[2023-10-24 10:00:10] [WARN] Memory threshold exceeded (500MB).
[2023-10-24 10:00:12] [WARN] Memory threshold exceeded (900MB).
[2023-10-24 10:00:15] [CRITICAL] OOM Killed during REQ-103.
EOF

    cat << 'EOF' > /home/user/app/processor.py
import math

def compute_trajectory(start_val, lr):
    history = []
    val = float(start_val)
    # Failsafe limit to prevent infinite loops, but too large for memory
    MAX_ITER = 5000000 

    while True:
        history.append(val)

        # Simple gradient descent step for f(x) = x^3 / 3 - 2x
        # Derivative is x^2 - 2
        step = lr * (val ** 2 - 2)
        val = val - step

        # Convergence check
        if abs(step) < 1e-8:
            break

        if len(history) > MAX_ITER:
            break

    return history
EOF

    cat << 'EOF' > /home/user/app/test_suite.py
from processor import compute_trajectory
import sys

def run_tests():
    # Test normal convergence
    hist1 = compute_trajectory(1.0, 0.1)
    assert len(hist1) < 100, "Should converge quickly"

    # Test divergence fix
    hist2 = compute_trajectory(2.0, 1.5)
    assert len(hist2) < 1000, "Should break on NaN/Inf quickly and not leak memory"

    print("OK")

if __name__ == "__main__":
    try:
        run_tests()
    except Exception as e:
        print(f"FAIL: {e}")
        sys.exit(1)
EOF

    chmod +x /home/user/app/test_suite.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
