#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app
    cat << 'EOF' > /app/api_server.py
#!/usr/bin/env python3
from flask import Flask, request

app = Flask(__name__)

@app.route('/submit', methods=['POST'])
def submit():
    data = request.get_data(as_text=True)
    with open('/tmp/input_stream.csv', 'a') as f:
        f.write(data)
        if not data.endswith('\n'):
            f.write('\n')
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/redis_forwarder.py
#!/usr/bin/env python3
import time
import redis
import os

r = redis.Redis(host='localhost', port=6379, db=0)
filename = '/tmp/output_stream.csv'

while not os.path.exists(filename):
    time.sleep(0.5)

with open(filename, 'r') as f:
    while True:
        line = f.readline()
        if not line:
            time.sleep(0.1)
            continue
        r.rpush('anomalies', line.strip())
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/reference_analyzer.py
#!/usr/bin/env python3
import sys
import csv
import re
import math

def process():
    reader = csv.reader(sys.stdin)
    writer = csv.writer(sys.stdout)
    window = []

    for row in reader:
        if not row: continue
        event_id = row[0]
        raw_text = row[2] if len(row) > 2 else ""

        normalized = re.sub(r'[^a-z0-9 ]', ' ', raw_text.lower())
        normalized = re.sub(r'\s+', ' ', normalized).strip()
        tokens = normalized.split() if normalized else []
        token_count = len(tokens)

        if len(window) < 20:
            score = 0.0
        else:
            mean = sum(window) / 20.0
            variance = sum((x - mean)**2 for x in window) / 20.0
            std_dev = math.sqrt(variance)
            if std_dev == 0:
                score = 0.0
            else:
                score = abs(token_count - mean) / std_dev

        writer.writerow([event_id, token_count, f"{score:.4f}"])
        sys.stdout.flush()

        window.append(token_count)
        if len(window) > 20:
            window.pop(0)

if __name__ == '__main__':
    process()
EOF

    chmod +x /app/*.py /opt/oracle/*.py
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
