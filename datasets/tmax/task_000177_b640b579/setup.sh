#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/sim_env
    cd /home/user/sim_env

    cat << 'EOF' > sim.py
import csv
import math
import sys

def calculate_std_dev(positions):
    n = len(positions)
    if n < 2: return 0.0
    # BUG: Catastrophic cancellation for values close to each other but large in magnitude
    sum_sq = sum(p**2 for p in positions)
    sq_sum = sum(positions)**2
    var = (sum_sq - sq_sum / n) / (n - 1)
    return math.sqrt(var)

def simulate_steps(pos, t, max_t, dt):
    # BUG: Floating point boundary condition. t will hit 1.0000000000000002 > max_t but 
    # if it exactly hits 1.0 (or slightly less due to precision), it might do an extra step or 
    # in this specific setup, they missed the base case entirely and just used `t > max_t + 0.1` 
    # Let's make the bug an explicit off-by-one/float comparison bug.
    if t > max_t + 0.05:
        return pos
    return simulate_steps(pos + 1.5 * dt, t + dt, max_t, dt)

def run(input_file):
    sys.setrecursionlimit(200) # Ensure it crashes quickly if infinite
    with open(input_file, 'r') as f:
        data = [float(line.strip()) for line in f if line.strip()]

    final_positions = []
    for pos in data:
        # 10 steps of 0.1
        final_positions.append(simulate_steps(pos, 0.0, 1.0, 0.1))

    std_dev = calculate_std_dev(final_positions)
    return std_dev

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    print(run(sys.argv[1]))
EOF

    cat << 'EOF' > inputs.csv
10.1
10.2
10.3
10.15
10.25
10000000.0000001
10000000.0000002
10.4
10.5
10.6
EOF

    cat << 'EOF' > container_crash.log
[ERROR] 2023-10-27T10:00:00Z - Container crashed with exit code 1
Traceback (most recent call last):
  File "sim.py", line 39, in <module>
    print(run(sys.argv[1]))
  File "sim.py", line 32, in run
    final_positions.append(simulate_steps(pos, 0.0, 1.0, 0.1))
  File "sim.py", line 22, in simulate_steps
    return simulate_steps(pos + 1.5 * dt, t + dt, max_t, dt)
  ...
RecursionError: maximum recursion depth exceeded in comparison
EOF

    chmod +x sim.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
