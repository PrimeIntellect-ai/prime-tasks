#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git redis-server curl
    pip3 install pytest flask redis requests

    # Create directories
    mkdir -p /app/api
    mkdir -p /app/worker/logs
    mkdir -p /app/data

    # Setup API and git history
    cd /app/api
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > app.py
import os
import json
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

API_SECRET_TOKEN = "sk-ops-99812-secret"

@app.route('/ingest', methods=['POST'])
def ingest():
    auth_header = request.headers.get('Authorization')
    if not auth_header or auth_header != f"Bearer {API_SECRET_TOKEN}":
        return jsonify({"error": "Unauthorized"}), 401

    payload = request.json
    r.lpush('log_queue', json.dumps(payload))
    return jsonify({"status": "ok"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    git add app.py
    git commit -m "Initial commit with API token"

    sed -i 's/API_SECRET_TOKEN = "sk-ops-99812-secret"/API_SECRET_TOKEN = os.environ.get("API_SECRET_TOKEN")/' app.py
    git add app.py
    git commit -m "Remove hardcoded API token for security"

    # Setup inject.py
    cat << 'EOF' > /app/inject.py
import json
import requests
import time

def main():
    with open('/app/data/payloads.jsonl', 'r') as f:
        for line in f:
            payload = json.loads(line)
            try:
                response = requests.post('http://localhost:5000/ingest', json=payload)
                if response.status_code != 200:
                    print(f"Failed to ingest: {response.status_code}")
            except Exception as e:
                print(f"Connection error: {e}")
            time.sleep(0.001)

if __name__ == '__main__':
    main()
EOF

    # Setup worker processor
    cat << 'EOF' > /app/worker/processor.py
import redis
import json
import sqlite3
import base64
import binascii

r = redis.Redis(host='localhost', port=6379, db=0)

def init_db():
    conn = sqlite3.connect('/app/data/processed.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS logs (id TEXT, message TEXT)''')
    conn.commit()
    return conn

def process():
    conn = init_db()
    c = conn.cursor()
    while True:
        item = r.blpop('log_queue', timeout=1)
        if not item:
            continue

        _, data = item
        payload = json.loads(data)

        msg_b64 = payload.get('message_b64', '')
        decoded = base64.b64decode(msg_b64).decode('utf-8')

        c.execute("INSERT INTO logs (id, message) VALUES (?, ?)", (payload.get('id'), decoded))
        conn.commit()

if __name__ == '__main__':
    process()
EOF

    # Setup start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/api && python3 app.py &
cd /app/worker && python3 processor.py > /app/worker/logs/worker.log 2>&1 &
echo "Services started."
EOF
    chmod +x /app/start_services.sh

    # Generate payloads
    python3 -c '
import json
import base64

with open("/app/data/payloads.jsonl", "w") as f:
    for i in range(1000):
        if i % 100 == 0:
            data = {
                "id": str(i),
                "message_b64": "invalid_base64!!!",
                "is_corrupted": True
            }
        else:
            data = {
                "id": str(i),
                "message_b64": base64.b64encode(f"Message {i}".encode()).decode(),
                "is_corrupted": False
            }
        f.write(json.dumps(data) + "\n")
'

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user
