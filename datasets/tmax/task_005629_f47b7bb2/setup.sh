#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/heat_sim.py
import math

def compute_heat(N, num_chunks=4):
    dx = 1.0 / N
    dy = 1.0 / N

    total_heat = 0.0
    chunk_size = N // num_chunks

    values = []
    for i in range(num_chunks):
        start = i * chunk_size
        end = N if i == num_chunks - 1 else (i + 1) * chunk_size

        chunk_sum = 0.0
        for x in range(start, end):
            for y in range(N):
                val = math.sin((x + 0.5) * dx) * math.cos((y + 0.5) * dy) * 0.01
                chunk_sum += val
        values.append(chunk_sum)

    for v in values:
        total_heat += v

    return total_heat
EOF

    cat << 'EOF' > /home/user/setup_obs.py
import numpy as np
import math

# Generate obs data
N_obs = 64
data = []
for x in range(N_obs):
    for y in range(N_obs):
        val = math.sin((x + 0.5) * (1.0/N_obs)) * math.cos((y + 0.5) * (1.0/N_obs)) * 0.01 + 1e-5
        data.append(val)

with open('/home/user/obs_data.txt', 'w') as f:
    f.write(','.join(map(str, data)))
EOF
    python3 /home/user/setup_obs.py

    cat << 'EOF' > /home/user/solve.py
import math
import json
import numpy as np

def compute_heat_fixed(N):
    dx = 1.0 / N
    dy = 1.0 / N
    vals = []
    for x in range(N):
        for y in range(N):
            val = math.sin((x + 0.5) * dx) * math.cos((y + 0.5) * dy) * 0.01
            vals.append(val)
    return math.fsum(vals)

prev = compute_heat_fixed(10)
converged_N = None
converged_value = None

for N in [20, 40, 80, 160, 320]:
    curr = compute_heat_fixed(N)
    if abs(curr - prev) < 1e-6:
        converged_N = N
        converged_value = curr
        break
    prev = curr

with open('/home/user/obs_data.txt', 'r') as f:
    obs_vals = [float(x) for x in f.read().split(',')]
obs_value = math.fsum(obs_vals)

res = {
    "converged_N": converged_N,
    "converged_value": converged_value,
    "obs_value": obs_value
}
with open('/home/user/expected.json', 'w') as f:
    json.dump(res, f)
EOF
    python3 /home/user/solve.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
