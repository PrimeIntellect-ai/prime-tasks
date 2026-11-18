#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    # Generate data.txt with large numbers and small variance
    python3 -c "
import random
random.seed(42)
with open('data.txt', 'w') as f:
    for _ in range(10000):
        val = 1000000.0 + random.random()
        f.write(f'{val:.6f}\n')
"

    # Create the buggy calc_variance.py
    cat << 'EOF' > /home/user/calc_variance.py
import sys

def read_data(filename):
    with open(filename, 'r') as f:
        return [float(line.strip()) for line in f]

def compute_variance(data):
    n = len(data)
    sum_sq = 0.0
    sum_x = 0.0

    rolling_vars = [0.0] * n

    # Boundary/off-by-one bug: loop goes from 1 to n (inclusive), 
    # but rolling_vars only has indices 0 to n-1. When i == n, rolling_vars[i] crashes.
    for i in range(1, n + 1):
        val = data[i-1]
        sum_x += val
        sum_sq += val * val

        # Performance bug: Opening file inside the loop causes massive syscall overhead
        with open('/home/user/progress.log', 'a') as f:
            f.write(f"Processed step {i}\n")

        if i > 1:
            # Precision loss: Naive variance calculation on large numbers
            mean = sum_x / i
            var = (sum_sq - i * mean * mean) / (i - 1)
            rolling_vars[i] = var  # Crashes here when i == n

    return rolling_vars[-1]

if __name__ == "__main__":
    data = read_data('/home/user/data.txt')
    try:
        # Clear progress log initially
        open('/home/user/progress.log', 'w').close()
        final_var = compute_variance(data)
        with open('/home/user/result.txt', 'w') as f:
            f.write(f"{final_var:.6f}\n")
    except Exception as e:
        with open('/home/user/error.log', 'w') as f:
            f.write(str(e))
        sys.exit(1)
EOF
    chmod +x /home/user/calc_variance.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
