#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /tmp/gen_expected.py
import pandas as pd

k = 1.5
c = 0.2
dt = 0.1
steps = 50
x0_list = [1.0, 2.0, 3.0]

records = []

for x0 in x0_list:
    x = x0
    v = 0.0
    t = 0.0
    for _ in range(steps + 1):
        records.append({'t': f"{t:.4f}", 'x': f"{x:.4f}", 'v': f"{v:.4f}", 'x0': f"{x0:.1f}"})

        # Forward Euler
        x_new = x + v * dt
        v_new = v + (-k * x - c * v) * dt

        x = x_new
        v = v_new
        t += dt

df = pd.DataFrame(records)
df.to_csv('/tmp/expected_training_data.csv', index=False)
EOF
    python3 /tmp/gen_expected.py
    rm /tmp/gen_expected.py

    chmod -R 777 /home/user
