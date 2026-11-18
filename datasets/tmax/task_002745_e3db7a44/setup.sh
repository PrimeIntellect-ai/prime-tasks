#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    python3 -c '
import os
os.makedirs("/home/user", exist_ok=True)
with open("/home/user/graph.txt", "w") as f:
    for y in range(10):
        for x in range(10):
            u = y * 10 + x
            if x < 9:
                v = y * 10 + (x + 1)
                f.write(f"{u} {v}\n")
            if y < 9:
                v = (y + 1) * 10 + x
                f.write(f"{u} {v}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
