#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git imagemagick fonts-dejavu-core
    pip3 install pytest numpy

    mkdir -p /home/user/diffusion_sim/data
    mkdir -p /home/user/diffusion_sim/output
    mkdir -p /app

    # Generate initial_states.csv and hidden_truth.npy
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np

# Generate CSV
np.random.seed(42)
data = np.random.uniform(0.1, 5.0, 10000)
lines = [f"{x:.4f}\n" for x in data]
lines[452] = "ERR_CORRUPT\n"
lines[8921] = "NaN_STR\n"
with open('/home/user/diffusion_sim/data/initial_states.csv', 'w') as f:
    f.writelines(lines)

# Generate Truth
np.random.seed(42)
data2 = np.random.uniform(0.1, 5.0, 10000)
data2 = np.delete(data2, [452, 8921])

kappa = 0.885
tau = 1.420
steps = 50

states = np.array(data2)
for _ in range(steps):
    denominator = np.abs(states - 2.0) + 1e-8
    states = states - kappa * (states / denominator) * np.exp(-tau)

np.save('/app/hidden_truth.npy', states)
EOF
    python3 /tmp/gen_data.py

    # Write math_core.py
    cat << 'EOF' > /home/user/diffusion_sim/math_core.py
import numpy as np

def step_forward(state, kappa, tau):
    # BUG: division by zero when state approaches 2.0
    # FIX: denominator should be (np.abs(state - 2.0) + 1e-8) or similar safely handled math
    # Intended logic for the agent to fix: state = state - kappa * (state / (state - 2.0))
    # Corrected logic should be: state = state - kappa * (state / (np.abs(state - 2.0) + 1e-8))
    # For simplicity of the truth generation, the expected fix is exactly adding 1e-8.

    denominator = state - 2.0
    return state - kappa * (state / denominator) * np.exp(-tau)
EOF

    # Write run_sim.py
    cat << 'EOF' > /home/user/diffusion_sim/run_sim.py
import json
import numpy as np
import os
from math_core import step_forward

def main():
    with open('model_config.json', 'r') as f:
        config = json.load(f)

    steps = config['iterations']

    # READ IMAGE PARAMS HERE
    kappa = None # TODO: read from notes
    tau = None   # TODO: read from notes

    with open('data/initial_states.csv', 'r') as f:
        raw_data = f.readlines()

    states = []
    for line in raw_data:
        states.append(float(line.strip())) # Will crash on corrupted lines

    states = np.array(states)

    for _ in range(steps):
        states = step_forward(states, kappa, tau)

    np.save('output/final_series.npy', states)

if __name__ == "__main__":
    main()
EOF

    # Git setup
    cd /home/user/diffusion_sim
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"
    echo '{"iterations": 50, "dt": 0.01}' > model_config.json
    git add run_sim.py math_core.py model_config.json
    git commit -m "Initial commit with config"
    rm model_config.json
    git add -u
    git commit -m "Accidentally removed config"

    # Generate Image
    convert -size 800x100 xc:white -fill black -pointsize 24 -annotate +10+50 'Set kappa=0.885 and tau=1.420 in the main script.' /app/handover_notes.png

    # User setup
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
