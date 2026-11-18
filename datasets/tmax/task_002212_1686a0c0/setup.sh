#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk grep sed
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import random
random.seed(42)
endpoints = ['/api/v1/auth', '/api/v1/data', '/api/v2/submit', '/health']
with open('/home/user/raw_app.log', 'w') as f:
    for i in range(200):
        # Noise
        f.write(f"2023-10-01T12:0{i%10}:{i%60:02d}Z [DEBUG] Connection pool initialized\n")
        f.write(f"2023-10-01T12:0{i%10}:{i%60:02d}Z [INFO] Worker {i%4} heartbeat\n")

        # Metrics
        ep = endpoints[i % len(endpoints)]
        latency = random.randint(10, 500)
        status = random.choice([200, 200, 200, 201, 400, 500])
        f.write(f"2023-10-01T12:0{i%10}:{i%60:02d}Z [METRIC] endpoint={ep} latency={latency}ms status={status} worker={i%4}\n")
EOF
    python3 /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
