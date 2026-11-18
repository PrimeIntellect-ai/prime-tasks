#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/generate_logs.py
import json
import random
from datetime import datetime, timedelta

random.seed(42)
start_time = datetime(2023, 1, 1, 0, 0, 0)
event_types = ['login', 'logout', 'view', 'purchase']

with open('/home/user/data/logs.jsonl', 'w', encoding='utf-8') as f:
    for i in range(10000):
        ts = start_time + timedelta(minutes=random.randint(0, 3000))
        etype = event_types[i % 4]
        msg = "User action occurred successfully."

        line = json.dumps({"ts": ts.strftime("%Y-%m-%dT%H:%M:%SZ"), "type": etype, "msg": msg})

        if random.random() < 0.05: # 5% of lines are malformed
            # break the json by adding a truncated unicode escape at the end of the message
            line = line[:-2] + '\\uD8' + '\"}'

        f.write(line + '\n')
EOF
    python3 /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
