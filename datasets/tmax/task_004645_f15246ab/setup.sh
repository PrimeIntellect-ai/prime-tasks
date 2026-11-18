#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server netcat curl gcc libc6-dev
pip3 install pytest flask redis

mkdir -p /app/data
mkdir -p /home/user

cat << 'EOF' > /app/data/evil_logs.txt
{"id": 1, "timestamp": "2023-10-25T14:35:22Z", "ssn": "123-45-6789", "email": "alice@corp.com"}
{"id": 2, "timestamp": "2023-10-25T14:36:01Z", "ssn": "987-65-4321", "email": "bob.smith@webmail.org"}
EOF

cat << 'EOF' > /app/data/clean_logs.txt
{"id": 3, "timestamp": "2023-10-25T14:35:50Z", "product_code": "123-45-6789", "message": "User logged in at server@domain.com"}
{"id": 4, "timestamp": "2023-10-25T14:38:10Z", "ref_id": "000-00-0000", "text": "Contact support via email"}
EOF

cat << 'EOF' > /app/log_producer.py
import socket
import time

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('localhost', 9001))
    server.listen(1)

    with open('/app/data/evil_logs.txt') as f:
        evil = f.readlines()
    with open('/app/data/clean_logs.txt') as f:
        clean = f.readlines()

    logs = evil + clean

    while True:
        try:
            conn, addr = server.accept()
            with conn:
                while True:
                    for log in logs:
                        conn.sendall(log.encode('utf-8'))
                        time.sleep(0.1)
        except Exception:
            pass

if __name__ == '__main__':
    start_server()
EOF

cat << 'EOF' > /app/stats_api.py
from flask import Flask, jsonify
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/stats')
def stats():
    logs = r.lrange('cleaned_logs', 0, -1)
    counts = {}
    for log in logs:
        try:
            data = json.loads(log)
            tb = data.get('time_bucket', 'unknown')
            counts[tb] = counts.get(tb, 0) + 1
        except:
            pass
    return jsonify(counts)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/log_producer.py &
python3 /app/stats_api.py &
EOF

chmod +x /app/start_services.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
