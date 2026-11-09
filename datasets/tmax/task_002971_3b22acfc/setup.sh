#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest watchdog

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/simulate_incoming.py
import os
import time
import shutil

incoming = "/home/user/incoming_gcode"
os.makedirs(incoming, exist_ok=True)

files = [
    ("print1.gcode", "G1 X10 Y10\nG1 Z0.2\n; filament used [mm] = 15.4\nM104 S0\n"),
    ("print2.gcode", "G28\nG1 X20 Y20\n; filament used [mm] = 3.2\nM140 S0\n"),
    ("print3.gcode", "M109 S200\nG1 X30 Y30\n; filament used [mm] = 100.0\nM104 S0\n"),
]

for fname, content in files:
    temp_path = f"/tmp/{fname}"
    with open(temp_path, "w") as f:
        f.write(content)
    # atomic move
    shutil.move(temp_path, os.path.join(incoming, fname))
    time.sleep(1)
EOF
    chmod +x /home/user/simulate_incoming.py

    chmod -R 777 /home/user
