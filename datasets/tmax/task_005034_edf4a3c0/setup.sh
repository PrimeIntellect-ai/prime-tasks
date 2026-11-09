#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server netcat curl jq
    pip3 install pytest flask redis requests

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create receiver.py
    cat << 'EOF' > /app/receiver.py
import os
import sys
import json
import subprocess
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)

REDIS_URL = os.environ.get('REDIS_URL', 'redis://127.0.0.1:6379/0')
FILTER_SCRIPT = os.environ.get('FILTER_SCRIPT')

try:
    r = redis.from_url(REDIS_URL)
    r.ping()
except Exception as e:
    print(f"Receiver failed to connect to Redis: {e}")
    sys.exit(1)

@app.route('/telemetry', methods=['POST'])
def telemetry():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400

    if not FILTER_SCRIPT or not os.path.isfile(FILTER_SCRIPT):
        return jsonify({"error": "Filter script missing"}), 500

    try:
        proc = subprocess.run(
            [FILTER_SCRIPT],
            input=json.dumps(data).encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        if proc.returncode != 0:
            return jsonify({"error": "Payload rejected by filter"}), 403
    except Exception as e:
        return jsonify({"error": f"Filter execution failed: {e}"}), 500

    r.lpush('telemetry_queue', json.dumps(data))
    return jsonify({"status": "accepted"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create worker.py
    cat << 'EOF' > /app/worker.py
import os
import sys
import json
import redis
import time

REDIS_URL = os.environ.get('REDIS_URL', 'redis://127.0.0.1:6379/0')

try:
    r = redis.from_url(REDIS_URL)
    r.ping()
except Exception as e:
    print(f"Worker failed to connect to Redis: {e}")
    sys.exit(1)

with open('/app/output.log', 'a') as f:
    f.write("Worker started\n")

while True:
    try:
        item = r.brpop('telemetry_queue', timeout=1)
        if item:
            _, data = item
            with open('/app/output.log', 'a') as f:
                f.write(f"Processed: {data.decode('utf-8')}\n")
    except Exception as e:
        print(f"Worker error: {e}")
        time.sleep(1)
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server &
python3 /app/receiver.py &
python3 /app/worker.py &
EOF
    chmod +x /app/start_services.sh

    # Generate corpora
    cat << 'EOF' > /app/corpora/clean/clean1.json
{"device_id": "DEV-1234", "timestamp": 1600000000, "metrics": {"temperature": 25.5, "humidity": 60}}
EOF
    cat << 'EOF' > /app/corpora/clean/clean2.json
{"device_id": "DEV-9999", "timestamp": 1600000001, "metrics": {"temperature": -50.0}}
EOF
    cat << 'EOF' > /app/corpora/clean/clean3.json
{"device_id": "DEV-0000", "timestamp": 1600000002, "metrics": {"temperature": 100.0, "pressure": 1013.25}}
EOF

    cat << 'EOF' > /app/corpora/evil/evil1.json
{"device_id": "DEV-1234", "timestamp": 1600000000, "metrics": {"temperature": 100.1}}
EOF
    cat << 'EOF' > /app/corpora/evil/evil2.json
{"device_id": "DEV-123", "timestamp": 1600000000, "metrics": {"temperature": 25.5}}
EOF
    cat << 'EOF' > /app/corpora/evil/evil3.json
{"device_id": "DEV-1234", "timestamp": "1600000000", "metrics": {"temperature": 25.5}}
EOF
    cat << 'EOF' > /app/corpora/evil/evil4.json
{"device_id": "DEV-1234", "timestamp": 1600000000, "metrics": {"temperature": 25.5}, "cmd": "reboot"}
EOF
    cat << 'EOF' > /app/corpora/evil/evil5.json
{"device_id": "DEV-1234", "timestamp": 1600000000, "metrics": {"temperature": -50.1}}
EOF
    cat << 'EOF' > /app/corpora/evil/evil6.json
{"device_id": "DEV-1234", "timestamp": 1600000000}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
