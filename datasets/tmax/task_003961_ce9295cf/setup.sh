#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc tar
    pip3 install pytest

    mkdir -p /home/user
    python3 -c '
import os
os.makedirs("/home/user", exist_ok=True)
with open("/home/user/project_logs.txt", "w") as f:
    for i in range(1, 501):
        if i == 45:
            f.write(f"Log entry {i}: User logged in with API_KEY=xyz123\n")
        elif i == 120:
            f.write(f"Log entry {i}: Action performed using API_KEY=abc999\n")
        else:
            f.write(f"Log entry {i}: Standard operation successful.\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
