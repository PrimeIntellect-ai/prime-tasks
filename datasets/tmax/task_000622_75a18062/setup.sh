#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis requests pandas

    mkdir -p /app/config /app/data /home/user

    cat << 'EOF' > /app/api.py
import os
import json
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host=os.environ.get("REDIS_HOST", "localhost"), port=int(os.environ.get("REDIS_PORT", 6379)))

@app.route('/', methods=['POST'])
def ingest():
    data = request.json
    r.lpush('sensor_data', json.dumps(data))
    return "OK"

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/archiver.py
import os
import json
import csv
import redis

r = redis.Redis(host=os.environ.get("REDIS_HOST", "localhost"), port=int(os.environ.get("REDIS_PORT", 6379)))
output_file = os.environ.get("OUTPUT_FILE", "/tmp/out.csv")

while True:
    _, msg = r.brpop('sensor_data')
    data = json.loads(msg)
    file_exists = os.path.isfile(output_file)
    with open(output_file, 'a', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=["timestamp", "sensor_A", "sensor_B", "sensor_C"])
        if not file_exists:
            writer.writeheader()
        writer.writerow(data)
EOF

    cat << 'EOF' > /app/generator.py
import requests
import time
import random

while True:
    data = {"timestamp": int(time.time()), "sensor_A": random.random(), "sensor_B": random.random(), "sensor_C": random.random()}
    try:
        requests.post("http://localhost:5000/", json=data)
    except:
        pass
    time.sleep(1)
EOF

    cat << 'EOF' > /app/config/api.env
REDIS_HOST=wrong_host
REDIS_PORT=9999
EOF

    cat << 'EOF' > /app/config/archiver.env
REDIS_HOST=wrong_host
REDIS_PORT=9999
OUTPUT_FILE=/tmp/wrong.csv
EOF

    cat << 'EOF' > /app/data/metadata.csv
sensor_id,location,threshold
sensor_A,North Wing,75.0
sensor_B,South Wing,80.0
sensor_C,East Wing,50.0
EOF

    cat << 'EOF' > /app/oracle_processor.py
import sys, pandas as pd, json
def process(input_csv, meta_csv):
    df = pd.read_csv(input_csv)
    meta = pd.read_csv(meta_csv)
    df = df.melt(id_vars=['timestamp'], var_name='sensor_id', value_name='value').dropna(subset=['value'])
    df = df.merge(meta, on='sensor_id')
    df = df.sort_values(['sensor_id', 'timestamp'])
    df['rolling_avg'] = df.groupby('sensor_id')['value'].transform(lambda x: x.rolling(3, min_periods=1).mean().round(2))
    df = df[df['rolling_avg'] > df['threshold']]
    df = df.sort_values(['timestamp', 'sensor_id'])
    res = df[['timestamp', 'sensor_id', 'location', 'value', 'rolling_avg']].to_dict(orient='records')
    print(json.dumps(res))

if __name__ == '__main__':
    process(sys.argv[1], sys.argv[2])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
