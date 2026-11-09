#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest flask

    # Create directories
    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/api
    mkdir -p /home/user/app/data

    # Create analyzer.c
    cat << 'EOF' > /home/user/app/backend/analyzer.c
#include <stdio.h>

typedef struct {
    int user_id;
    int attempts;
} AnalyticsPayload;

double compute_risk_score(AnalyticsPayload* payload) {
    return (payload->attempts * 1.5) + (payload->user_id % 10);
}
EOF

    # Create backend_tcp.py skeleton
    cat << 'EOF' > /home/user/app/backend/backend_tcp.py
import socket
import json
import ctypes

# TODO: Define AnalyticsPayload struct using ctypes
# TODO: Load libanalyzer.so and define compute_risk_score signature

def process_payload(data):
    # TODO: Convert data dict to AnalyticsPayload and call compute_risk_score
    pass

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9090))
    server.listen(5)
    print("Backend TCP listening on 127.0.0.1:9090")
    while True:
        client, _ = server.accept()
        data = client.recv(1024).decode('utf-8')
        if data:
            payload = json.loads(data)
            score = process_payload(payload)
            client.send(json.dumps({'risk_score': score}).encode('utf-8'))
        client.close()

if __name__ == '__main__':
    start_server()
EOF

    # Create legacy_validate.js
    cat << 'EOF' > /home/user/app/api/legacy_validate.js
function validatePayload(payload) {
    if (!payload.user_id || !payload.event_type || !payload.metadata) {
        return false;
    }
    if (payload.metadata.attempts > 5) {
        return false;
    }
    return true;
}
EOF

    # Create ingest_api.py skeleton
    cat << 'EOF' > /home/user/app/api/ingest_api.py
from flask import Flask, request, jsonify
import socket
import json

app = Flask(__name__)

# TODO: Translate validatePayload from legacy_validate.js

@app.route('/ingest', methods=['POST'])
def ingest():
    payload = request.json
    # TODO: Validate payload. Return 400 {"error": "Validation failed"} if invalid.

    # TODO: Send payload to backend_tcp.py on 127.0.0.1:9090 and get risk_score
    risk_score = 0.0 # Placeholder

    return jsonify({"status": "success", "risk_score": risk_score})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # Create SQLite database and seed data
    sqlite3 /home/user/app/data/analytics.db << 'EOF'
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    timestamp INTEGER NOT NULL
);
INSERT INTO events (event_type, timestamp) VALUES ('login', 1696517280);
INSERT INTO events (event_type, timestamp) VALUES ('purchase', 1696520880);
INSERT INTO events (event_type, timestamp) VALUES ('logout', 1696524480);
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
