#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq parallel gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_logs.py
import json
import random
import time

statuses = [200, 404, 500]
user_agents = [
    "Mozilla/5.0",
    "BadBot\\u002Z/1.0",
    "Chrome/91.0",
    "Safari\\u12/537"
]

with open("/home/user/raw_logs.jsonl", "w") as f:
    for i in range(100):
        status = random.choice(statuses)
        ua = random.choice(user_agents)
        ip = str(random.randint(1, 255)) + "." + str(random.randint(1, 255)) + "." + str(random.randint(1, 255)) + "." + str(random.randint(1, 255))

        if i % 2 == 0:
            ts = int(time.time()) - random.randint(0, 100000)
        else:
            ts = "12/Oct/2023:14:22:11"

        line = '{"timestamp": "' + str(ts) + '", "ip_address": "' + ip + '", "status": ' + str(status) + ', "user_agent": "' + ua + '", "extra_data": "ignore_me"}\n'
        f.write(line)
EOF

    python3 /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
