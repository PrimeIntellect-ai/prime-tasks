#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Generate the raw mesh data
    python3 -c '
import os

os.makedirs("/home/user/raw_mesh_data", exist_ok=True)

def get_quadrant_base(x, y):
    if x < 5 and y < 5: return 5.0
    if x >= 5 and y < 5: return 15.0
    if x < 5 and y >= 5: return 25.0
    if x >= 5 and y >= 5: return 35.0
    return 0.0

for x in range(10):
    for y in range(10):
        filepath = f"/home/user/raw_mesh_data/sensor_{x}_{y}.csv"
        base_peak = get_quadrant_base(x, y)
        with open(filepath, "w") as f:
            f.write("frequency,intensity\n")
            for freq in range(500, 2010, 10):
                intensity = 1.0
                if freq == 1200:
                    intensity = base_peak  # Max value in the 1000-1500 range
                f.write(f"{freq},{intensity}\n")
'

    # Set permissions
    chmod -R 777 /home/user
