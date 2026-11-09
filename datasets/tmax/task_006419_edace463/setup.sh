#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create directories
mkdir -p /home/user/logs
mkdir -p /home/user/service

# Generate Logs
cat << 'EOF' > /home/user/logs/gatherer.log
2024-10-27T03:14:10Z INFO: Gathering metrics...
2024-10-27T03:14:12Z INFO: Metrics gathered successfully.
2024-10-27T03:14:14Z INFO: Gathering metrics...
EOF

cat << 'EOF' > /home/user/logs/predictor.log
2024-10-27T03:14:11Z INFO: Predicting scale factor...
2024-10-27T03:14:11Z INFO: Scale factor computed: 1.05
2024-10-27T03:14:15Z ERROR: ValueError: math domain error in compute_volatility
2024-10-27T03:14:20Z ERROR: ValueError: math domain error in compute_volatility
EOF

cat << 'EOF' > /home/user/logs/scaler.log
2024-10-27T03:14:11Z INFO: Applying scale factor 1.05
2024-10-27T03:14:15Z ERROR: Scaler failed: received NaN/Invalid from predictor service!
2024-10-27T03:14:20Z ERROR: Scaler failed: received NaN/Invalid from predictor service!
EOF

# Generate Buggy Python Service
cat << 'EOF' > /home/user/service/predictor.py
import math

def compute_volatility(data):
    if not data:
        return 0.0
    # Naive variance E[X^2] - (E[X])^2
    # Suffers from catastrophic cancellation with large values
    mean_sq = sum(x**2 for x in data) / len(data)
    sq_mean = (sum(data) / len(data))**2
    return math.sqrt(mean_sq - sq_mean)
EOF

# Generate Broken Build Script
cat << 'EOF' > /home/user/service/build.py
import sys
from predictor import compute_volatility

def run_tests():
    print("Running tests...")
<<<<<<< HEAD
    res = compute_volatility([10.0, 12.0, 10.0])
=======
    res = compute_volatility([10.0, 10.0, 10.0])
>>>>>>> hotfix-branch
    print("Tests passed.")

if __name__ == "__main__":
    try:
        run_tests()
        sys.exit(0)
    except SyntaxError:
        sys.exit(1)
    except Exception as e:
        print(f"Build failed with exception: {e}")
        sys.exit(1)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
