#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hey, it's Dave. The attacker is exploiting a vulnerability that causes a noticeable latency spike. You need to calculate a rolling average of the response time over exactly five consecutive requests. When that five-request rolling average strictly exceeds eight hundred and fifty milliseconds, you've found the changepoint. Every request from that point forward until the end of the log should be considered part of the anomaly."

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import csv
import json
import random
import os

os.makedirs('/home/user', exist_ok=True)

rows = []
for i in range(1, 101):
    ip = f"192.168.1.{random.randint(10, 50)}"
    if i % 7 == 0:
        ua = "Mozilla/5.0\n(Windows NT 10.0; Win64; x64)\nEvilPayload"
    else:
        ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

    if i < 75:
        rt = random.randint(100, 300)
    else:
        rt = random.randint(900, 1100)

    rows.append({"id": i, "timestamp": f"2023-10-01T12:00:{i:02d}Z", "ip_address": ip, "user_agent": ua, "response_time": rt})

with open('/home/user/server_logs.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["id", "timestamp", "ip_address", "user_agent", "response_time"])
    writer.writeheader()
    writer.writerows(rows)

threat_intel = {
    f"192.168.1.{i}": "APT-29" for i in range(40, 51)
}
with open('/home/user/threat_intel.json', 'w') as f:
    json.dump(threat_intel, f)

# Using chr(123) and chr(125) to avoid Apptainer build variable syntax errors
template = "Incident Report\n\nAnomalies Detected:\n{% for a in anomalies %}- " + chr(123)*2 + " a.timestamp " + chr(125)*2 + " | " + chr(123)*2 + " a.ip_address " + chr(125)*2 + " | " + chr(123)*2 + " a.actor_group " + chr(125)*2 + " | " + chr(123)*2 + " a.response_time " + chr(125)*2 + "ms\n{% endfor %}"
with open('/home/user/report_template.jinja', 'w') as f:
    f.write(template)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
