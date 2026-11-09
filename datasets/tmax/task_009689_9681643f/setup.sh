#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib

    mkdir -p /home/user/sim_data
    mkdir -p /home/user/plots

    # Generate exp_1.log
    cat << 'EOF' > /home/user/sim_data/exp_1.log
Simulation ID: 101
Mass (kg): 2.0
-- DATA START --
EOF
    python3 -c "
import math
for i in range(500):
    t = i * 0.01
    val = math.sin(2 * math.pi * 2.0 * t) + 0.1 * math.sin(2 * math.pi * 10 * t)
    print(f't={t:.3f}, val={val:.3f}')
" >> /home/user/sim_data/exp_1.log

    # Generate exp_2.log
    cat << 'EOF' > /home/user/sim_data/exp_2.log
Simulation ID: 102
Mass (kg): 1.5
-- DATA START --
EOF
    python3 -c "
import math
for i in range(500):
    t = i * 0.01
    val = math.cos(2 * math.pi * 3.5 * t) + 0.2 * math.cos(2 * math.pi * 15 * t)
    print(f't={t:.3f}, val={val:.3f}')
" >> /home/user/sim_data/exp_2.log

    # Create reference.csv
    cat << 'EOF' > /home/user/sim_data/reference.csv
exp_1.log,315.83
exp_2.log,725.71
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
