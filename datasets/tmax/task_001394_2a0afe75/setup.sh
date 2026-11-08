#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gzip
    pip3 install pytest flask requests

    mkdir -p /app/services
    mkdir -p /home/user/data/archives

    cat << 'EOF' > /app/services/start_all.sh
#!/bin/bash
mkdir -p /home/user/data/archives
python3 /app/services/api.py --port 9999 &
python3 /app/services/generator.py &
bash /app/services/archiver.sh &
EOF
    chmod +x /app/services/start_all.sh

    cat << 'EOF' > /app/services/generator.py
import time
import random
import json
import os

os.makedirs("/home/user/data", exist_ok=True)

truth = []
# Generate 500 records
for i in range(500):
    val = random.uniform(-10.0, 50.0)
    ts = f"2023-10-01T12:00:{i%60:02d}Z"
    sid = f"S{i%5}"

    if val >= 0.0:
        truth.append({"sensor_id": sid, "value": round(val, 2), "timestamp": ts})

    xml = f"<Reading>\n<SensorID>{sid}</SensorID>\n<Value>{val:.2f}</Value>\n<Timestamp>{ts}</Timestamp>\n</Reading>\n"

    enc = 'utf-8' if random.random() > 0.5 else 'latin-1'

    with open("/home/user/data/active.log", "ab") as f:
        f.write(xml.encode(enc))

    time.sleep(0.02)

with open("/app/services/truth_log.json", "w") as f:
    json.dump(truth, f)

# Keep alive
while True:
    time.sleep(1)
EOF

    cat << 'EOF' > /app/services/archiver.sh
#!/bin/bash
mkdir -p /home/user/data/archives
while true; do
    sleep 2
    if [ -f /home/user/data/active.log ]; then
        mv /home/user/data/active.log /home/user/data/active_tmp.log
        # Compress and simulate truncation by killing gzip mid-write sometimes
        gzip -c /home/user/data/active_tmp.log > /home/user/data/archives/log_$(date +%s%N).gz &
        PID=$!
        sleep 0.01
        kill -9 $PID 2>/dev/null || true
        rm -f /home/user/data/active_tmp.log
    fi
done
EOF

    cat << 'EOF' > /app/services/api.py
from flask import Flask, request, jsonify
import argparse
import logging

log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

app = Flask(__name__)
received_valid_count = 0

@app.route('/submit', methods=['POST'])
def submit():
    global received_valid_count
    data = request.json
    if data and data.get('value', -1) >= 0:
        received_valid_count += 1
    return jsonify({"status": "ok"})

@app.route('/metrics', methods=['GET'])
def metrics():
    return jsonify({"received_valid_count": received_valid_count})

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    app.run(host='127.0.0.1', port=args.port)
EOF

    # Create empty truth log just in case
    echo "[]" > /app/services/truth_log.json

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
