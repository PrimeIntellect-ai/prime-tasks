#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/generate_logs.py
import time
from datetime import datetime, timezone
import random
import hashlib

random.seed(42)

def generate_payload():
    return hashlib.md5(str(random.random()).encode()).hexdigest()[:8]

log_A = open('/home/user/logs/server_A.log', 'w')
log_B = open('/home/user/logs/server_B.log', 'w')

# Generate logs for 2024-01-15 08:00 to 08:30
start_epoch = 1705305600 # 2024-01-15 08:00:00 UTC

logs = []

for minute in range(30):
    num_requests = random.randint(5, 15)

    # Inject anomaly at 08:17
    if minute == 17:
        errors_to_inject = 4
        avg_time_target = 1200
    else:
        errors_to_inject = random.randint(0, 1)
        avg_time_target = 200

    for i in range(num_requests):
        ts = start_epoch + (minute * 60) + random.randint(0, 59)
        ip = f"192.168.1.{random.randint(1, 100)}"

        if errors_to_inject > 0:
            status = random.choice([500, 502, 503])
            errors_to_inject -= 1
        else:
            status = random.choice([200, 201, 404])

        if minute == 17:
            resp_time = random.randint(1000, 1500)
        else:
            resp_time = random.randint(50, 400)

        payload = generate_payload()

        # Format A: YYYY-MM-DD HH:MM:SS|IP|STATUS|RESPONSE_TIME_MS|PAYLOAD_HASH
        dt = datetime.fromtimestamp(ts, timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
        line_A = f"{dt}|{ip}|{status}|{resp_time}|{payload}\n"

        # Format B: EPOCH_TIME,IP,STATUS,RESPONSE_TIME_MS,PAYLOAD_HASH
        line_B = f"{ts},{ip},{status},{resp_time},{payload}\n"

        # Randomly distribute and create duplicates
        choice = random.random()
        if choice < 0.4:
            log_A.write(line_A)
        elif choice < 0.8:
            log_B.write(line_B)
        else:
            # Duplicate entry in both formats
            log_A.write(line_A)
            log_B.write(line_B)

log_A.close()
log_B.close()
EOF

    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
