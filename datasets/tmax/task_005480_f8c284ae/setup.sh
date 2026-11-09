#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    python3 -c '
import os
import json

csv_content = """id,value1,value2
1,0.5,2.0
,1.0,1.0
3,,3.0
4,2.0,-1.0
"""
with open("/home/user/dataset.csv", "w") as f:
    f.write(csv_content)

weights = {
    "w1": 0.5,
    "w2": -0.2,
    "w3": 0.1,
    "b": -0.1
}
with open("/home/user/model_weights.json", "w") as f:
    json.dump(weights, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
