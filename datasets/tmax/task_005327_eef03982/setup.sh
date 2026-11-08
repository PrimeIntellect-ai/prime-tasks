#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import json, random
random.seed(42)
data = []
for i in range(100000):
    status = "SUCCESS" if random.random() > 0.2 else "ERROR"
    val = random.uniform(10.0, 100.0)
    data.append({"id": i, "status": status, "value": val})
with open('/home/user/api_response.json', 'w') as f:
    json.dump(data, f)
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
