#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import json
import os

data = []
for i in range(1000):
    val = 10.0
    if 200 <= i <= 220:
        val = 100.0
    data.append({"pos": i, "val": val})

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/raw_data.json", "w") as f:
    json.dump(data, f)
'

    chmod -R 777 /home/user
