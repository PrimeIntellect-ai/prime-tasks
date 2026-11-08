#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server curl
pip3 install pytest flask redis requests

mkdir -p /app

cat << 'EOF' > /app/oracle_preprocessor.py
#!/usr/bin/env python3
import sys
import json
import math

def pearson(x, y):
    n = len(x)
    if n < 2: return 0.0
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y))
    var_x = sum((a - mean_x) ** 2 for a in x)
    var_y = sum((b - mean_y) ** 2 for b in y)
    if var_x == 0 or var_y == 0: return 0.0
    return num / math.sqrt(var_x * var_y)

def main():
    try:
        data = json.load(sys.stdin)
    except:
        print(json.dumps({"cleaned_data": [], "correlation": 0.0}))
        return

    cleaned = []
    valid_f1 = []
    valid_f2 = []

    for row in data:
        if not isinstance(row, dict) or "f1" not in row or "f2" not in row:
            continue

        v1 = row["f1"]
        v2 = row["f2"]

        if v1 is not None:
            v1 = max(-5.0, min(5.0, float(v1)))
            valid_f1.append(v1)
        else:
            v1 = sum(valid_f1) / len(valid_f1) if valid_f1 else 0.0

        if v2 is not None:
            v2 = max(-5.0, min(5.0, float(v2)))
            valid_f2.append(v2)
        else:
            v2 = sum(valid_f2) / len(valid_f2) if valid_f2 else 0.0

        cleaned.append({"f1": v1, "f2": v2})

    f1_arr = [r["f1"] for r in cleaned]
    f2_arr = [r["f2"] for r in cleaned]

    corr = pearson(f1_arr, f2_arr)

    print(json.dumps({"cleaned_data": cleaned, "correlation": round(corr, 4)}))

if __name__ == "__main__":
    main()
EOF
chmod +x /app/oracle_preprocessor.py

cat << 'EOF' > /app/experiment_api.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

metrics = []

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    r.lpush('experiment_queue', json.dumps(data))
    return jsonify({"status": "queued"})

@app.route('/log_metric', methods=['POST'])
def log_metric():
    data = request.json
    metrics.append(data)
    return jsonify({"status": "logged"})

@app.route('/metrics', methods=['GET'])
def get_metrics():
    return jsonify(metrics)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat << 'EOF' > /app/worker.py
import redis
import json
import time
import subprocess
import requests

# BUGGY CONFIGURATION (Agent must fix these)
r = redis.Redis(host='localhost', port=6380, db=0)
API_URL = "http://localhost:5001/log_metric"

def work():
    while True:
        try:
            item = r.brpop('experiment_queue', timeout=2)
            if item:
                data = item[1].decode('utf-8')
                result = subprocess.run(
                    ['python3', '/home/user/preprocessor.py'],
                    input=data,
                    text=True,
                    capture_output=True
                )
                if result.returncode == 0:
                    out_data = json.loads(result.stdout)
                    requests.post(API_URL, json=out_data)
        except Exception as e:
            time.sleep(1)

if __name__ == "__main__":
    work()
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/experiment_api.py &
python3 /app/worker.py &
EOF
chmod +x /app/start_services.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
