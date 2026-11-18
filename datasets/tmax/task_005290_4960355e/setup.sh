#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import shutil

base_dir = "/home/user/raw_projects"
os.makedirs(base_dir, exist_ok=True)

jobs = {
    "job_001": {
        "gcode": "; LAYER_COUNT: 50\nG1 X10 Y10\n",
        "log": "[2023-10-01 10:00:00] JOB START\n[2023-10-01 11:20:00] STATUS: SUCCESS\nDuration: 1h 20m\n"
    },
    "job_002": {
        "gcode": "; LAYER_COUNT: 150\nG1 X20 Y20\n",
        "log": "[2023-10-02 10:00:00] JOB START\n[2023-10-02 13:45:00] STATUS: SUCCESS\nDuration: 3h 45m\n"
    },
    "job_003": {
        "gcode": "; LAYER_COUNT: 200\nG1 X30 Y30\n",
        "log": "[2023-10-03 10:00:00] JOB START\n[2023-10-03 10:15:00] [ERROR] Thermal Runaway\n[2023-10-03 10:15:05] STATUS: FAILED\n"
    },
    "job_004": {
        "gcode": "; LAYER_COUNT: 120\nG1 X40 Y40\n",
        "log": "[2023-10-04 10:00:00] JOB START\n[2023-10-04 12:10:00] STATUS: SUCCESS\nDuration: 2h 10m\n"
    },
    "job_005": {
        "gcode": "; LAYER_COUNT: 300\nG1 X50 Y50\n",
        "log": "[2023-10-05 10:00:00] JOB START\n[2023-10-05 11:00:00] [ERROR] Filament runout\n[2023-10-05 15:00:00] STATUS: SUCCESS\nDuration: 5h 00m\n"
    }
}

for job, data in jobs.items():
    job_dir = os.path.join(base_dir, job)
    os.makedirs(job_dir, exist_ok=True)
    with open(os.path.join(job_dir, "model.gcode"), "w") as f:
        f.write(data["gcode"])
    with open(os.path.join(job_dir, "print_server.log"), "w") as f:
        f.write(data["log"])

tar_path = "/home/user/raw_projects.tar.gz"
with tarfile.open(tar_path, "w:gz") as tar:
    tar.add(base_dir, arcname="raw_projects")

shutil.rmtree(base_dir)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
