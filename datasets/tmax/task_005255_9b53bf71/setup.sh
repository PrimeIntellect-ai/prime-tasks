#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy

    mkdir -p /home/user/mc_sim

    cat << 'EOF' > /home/user/mc_sim/generate.py
#!/usr/bin/env python3
import sys
import numpy as np

if len(sys.argv) != 2:
    sys.exit(1)

run_idx = int(sys.argv[1])
np.random.seed(run_idx * 42)

# Generate a noisy signal
t = np.linspace(0, 10, 100)
signal = np.sin(2 * np.pi * 0.5 * t) + np.random.normal(0, 0.5, 100)

# To exaggerate floating point non-associativity, we add large variations
# based on run_idx
signal = signal + (run_idx * 1e5) - (run_idx * 1e5) + (run_idx * 1e-10)

out = [str(run_idx)] + [f"{x:.15e}" for x in signal]
print(",".join(out))
EOF
    chmod +x /home/user/mc_sim/generate.py

    cat << 'EOF' > /home/user/mc_sim/aggregate.sh
#!/bin/bash
# Run 100 iterations of Monte Carlo simulation in parallel
seq 1 100 | xargs -P 4 -I {} /home/user/mc_sim/generate.py {} | \
cut -d',' -f2- | \
awk -F',' '{
    for(i=1; i<=NF; i++) {
        sum[i] += $i
    }
} END {
    for(i=1; i<=NF; i++) {
        printf "%.15e%s", sum[i], (i==NF ? "\n" : ",")
    }
}' > /home/user/mc_sim/averaged_signal.txt
EOF
    chmod +x /home/user/mc_sim/aggregate.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
