#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c '
import numpy as np

np.random.seed(101)
x_vals = np.linspace(0, 10, 50)
y1_vals = 2.5 * x_vals + 1.2 + np.random.normal(0, 0.5, size=50)
y2_vals = 2.5 * x_vals + 1.4 + np.random.normal(0, 0.5, size=50)

lines = []
for x, y1, y2 in zip(x_vals, y1_vals, y2_vals):
    lines.append(f"S1,{x:.4f},{y1:.4f}\n")
    lines.append(f"S2,{x:.4f},{y2:.4f}\n")

np.random.shuffle(lines)

with open("/home/user/raw_observations.txt", "w") as f:
    f.writelines(lines)
'

    chmod -R 777 /home/user
