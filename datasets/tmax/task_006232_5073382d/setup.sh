#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs

    cat << 'EOF' > /tmp/setup.py
import os
import random
import json
from datetime import datetime, timezone, timedelta

os.makedirs('/home/user/logs', exist_ok=True)
random.seed(42)

start_time = int(datetime(2023, 10, 25, 0, 0, 0, tzinfo=timezone.utc).timestamp())
end_time = start_time + 86400

# We will inject massive failure spikes at specific 60-second intervals (multiples of 60)
spikes = [
    (start_time + 3600, 150),
    (start_time + 7200, 140),
    (start_time + 10800, 130),
    (start_time + 14400, 120),
    (start_time + 18000, 110),
    (start_time + 21600, 100),
    (start_time + 25200, 90),
    (start_time + 28800, 80),
    (start_time + 32400, 70),
    (start_time + 36000, 60)
]

web_f = open('/home/user/logs/web_server.log', 'w')
web_f.write("timestamp,ip,status_code,response_time\n")
api_f = open('/home/user/logs/api_gateway.jsonl', 'w')
db_f = open('/home/user/logs/db_query.log', 'w')

def generate_web(ts, is_err):
    dt = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
    ip = f"192.168.1.{random.randint(1, 255)}"
    status = random.choice([500, 502, 503]) if is_err else random.choice([200, 201, 301, 404])
    rt = random.randint(10, 500)
    web_f.write(f"{dt},{ip},{status},{rt}\n")

def generate_api(ts, is_err):
    ts_ms = ts * 1000 + random.randint(0, 999)
    ip = f"10.0.0.{random.randint(1, 255)}"
    ep = "/api/v1/resource"
    api_f.write(json.dumps({"ts": ts_ms, "client": ip, "endpoint": ep, "error": is_err}) + "\n")

def generate_db(ts, is_err):
    dt_str = datetime.fromtimestamp(ts, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
    user = f"user_{random.randint(1,10)}"
    dur = random.randint(1, 5000)
    st = "ERROR" if is_err else "OK"
    db_f.write(f"[{dt_str}] user={user} duration_ms={dur} status={st}\n")

# Background noise
for _ in range(50000):
    ts = random.randint(start_time, end_time - 1)
    # small chance of random error
    is_err = random.random() < 0.05
    choice = random.choice([1,2,3])
    if choice == 1: generate_web(ts, is_err)
    elif choice == 2: generate_api(ts, is_err)
    else: generate_db(ts, is_err)

# Spikes
for spike_start, count in spikes:
    for _ in range(count):
        ts = random.randint(spike_start, spike_start + 59)
        generate_web(ts, True)
        generate_api(ts, True)
        generate_db(ts, True)

web_f.close()
api_f.close()
db_f.close()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
