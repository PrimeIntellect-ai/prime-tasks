#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os

base_dir = "/home/user/research_data"
os.makedirs(os.path.join(base_dir, "experiment1"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "experiment2"), exist_ok=True)

# Create ISO-8859-1 text files
with open(os.path.join(base_dir, "experiment1", "meta.txt"), "wb") as f:
    f.write("Experiment 1: Temperature 220°C, Über fast print.\n".encode("iso-8859-1"))

with open(os.path.join(base_dir, "experiment2", "meta.txt"), "wb") as f:
    f.write("Experiment 2: Test with café settings.\n".encode("iso-8859-1"))

# Create GCode files
with open(os.path.join(base_dir, "experiment1", "run.gcode"), "w", encoding="utf-8") as f:
    f.write("G28\nG1 Z5 F5000\n; PRINT_TIME: 4500\nM104 S0\n")

with open(os.path.join(base_dir, "experiment2", "run.gcode"), "w", encoding="utf-8") as f:
    f.write("G28\n; PRINT_TIME: 3200\nG1 X10 Y10\nM104 S0\n")

# Create symlink loop
os.symlink(base_dir, os.path.join(base_dir, "loop_link"))
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
