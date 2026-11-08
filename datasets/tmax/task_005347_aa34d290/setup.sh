#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl sqlite3
    pip3 install pytest flask redis requests

    mkdir -p /app

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/flask_api.py > /app/flask.log 2>&1 &
nohup python3 /app/log_generator.py > /app/generator.log 2>&1 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/flask_api.py
from flask import Flask, request
import sqlite3
import json

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect('/app/clean_logs.db')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, log TEXT)')
    conn.commit()
    conn.close()

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data or 'logs' not in data:
        return {"error": "Invalid payload"}, 400

    conn = sqlite3.connect('/app/clean_logs.db')
    c = conn.cursor()
    for log in data['logs']:
        c.execute('INSERT INTO logs (log) VALUES (?)', (log,))
    conn.commit()
    conn.close()
    return {"status": "ok"}, 200

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/log_generator.py
import redis
import time
import random

r = redis.Redis(host='localhost', port=6379, db=0)

templates = [
    "User {email} logged in from {ip} using card {card}",
    "Failed login for {email} from {ip}",
    "Purchase by {email} with {card} from IP {ip}"
]

def generate_log():
    email = f"user{random.randint(1,100)}@example.com"
    ip = f"192.168.1.{random.randint(1,255)}"
    card = f"{random.randint(1000,9999)}-{random.randint(1000,9999)}-{random.randint(1000,9999)}-{random.randint(1000,9999)}"
    return random.choice(templates).format(email=email, ip=ip, card=card)

while True:
    try:
        r.rpush('raw_logs', generate_log())
    except redis.exceptions.ConnectionError:
        pass
    time.sleep(0.1)
EOF

    cat << 'EOF' > /app/verify.py
import sqlite3
import sys

def verify():
    try:
        conn = sqlite3.connect('/app/clean_logs.db')
        c = conn.cursor()
        c.execute('SELECT log FROM logs')
        logs = c.fetchall()
        if not logs:
            sys.exit(1)
        # Simplified verification for setup
        sys.exit(0)
    except Exception:
        sys.exit(1)

if __name__ == '__main__':
    verify()
EOF

    # Create the db file so it has correct permissions
    sqlite3 /app/clean_logs.db "CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, log TEXT);"
    chmod 666 /app/clean_logs.db

    # Start services for the environment if needed by a bashrc hack, but usually the test runner calls start_services.sh
    # We will inject it into bashrc just in case the test framework expects them running without calling the script
    echo "/app/start_services.sh" >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
