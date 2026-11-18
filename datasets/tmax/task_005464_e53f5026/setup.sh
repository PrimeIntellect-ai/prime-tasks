#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim_engine.py
import numpy as np

def run_simulation(dt, duration=50.0):
    omega = 50.0 # true angular freq = 50 rad/s -> ~7.957 Hz
    steps = int(duration / dt)
    x, v = 1.0, 0.0
    traj = []
    for _ in range(steps):
        traj.append(x)
        v = v - (omega**2)*x*dt
        x = x + v*dt
        if abs(x) > 1000:
            traj.extend([np.nan]*(steps - len(traj)))
            break
    return np.array(traj)
EOF

    cat << 'EOF' > /home/user/peptide.fasta
>sp|P12345|SYN_PEPTIDE Synthetic test peptide
MKVLAEFY
EOF

    chmod -R 777 /home/user
