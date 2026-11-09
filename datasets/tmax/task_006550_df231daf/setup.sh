#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.py
import sqlite3
from flask import Flask, request

app = Flask(__name__)

def get_db():
    return sqlite3.connect('test.db')

@app.route('/api/v1/users', methods=['GET'])
def get_user():
    user_id = request.args.get('id')
    db = get_db()
    # Safe: Parameterized query
    cursor = db.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    return {"data": cursor.fetchall()}

@app.route('/api/v1/search', methods=['GET'])
def search_items():
    query = request.args.get('q', '')
    db = get_db()
    # Vulnerable: String formatting
    sql = f"SELECT * FROM items WHERE name = '{query}' AND public = 1"
    try:
        cursor = db.execute(sql)
        return {"data": cursor.fetchall()}
    except:
        return {"error": "db error"}, 500

@app.route('/api/v1/status', methods=['GET'])
def status():
    return {"status": "ok"}
EOF

    cat << 'EOF' > /home/user/security_events.log
{"timestamp": "2023-10-25T09:00:00Z", "source_ip": "10.0.0.5", "method": "GET", "path": "/api/v1/users?id=1", "status_code": 200, "response_headers": {"Content-Type": "application/json", "Content-Security-Policy": "default-src 'none'"}}
{"timestamp": "2023-10-25T10:00:00Z", "source_ip": "192.168.1.50", "method": "GET", "path": "/api/v1/search?q=1%27%20UNION%20SELECT%201,2,3--", "status_code": 200, "response_headers": {"Content-Type": "application/json"}}
{"timestamp": "2023-10-25T10:15:00Z", "source_ip": "172.16.0.10", "method": "GET", "path": "/api/v1/search?q=apple", "status_code": 200, "response_headers": {"Content-Type": "application/json", "Strict-Transport-Security": "max-age=31536000"}}
{"timestamp": "2023-10-25T10:30:00Z", "source_ip": "192.168.1.100", "method": "GET", "path": "/api/v1/search?q=admin%27--", "status_code": 200, "response_headers": {"Content-Type": "application/json", "X-Powered-By": "Flask"}}
{"timestamp": "2023-10-25T10:45:00Z", "source_ip": "10.10.10.10", "method": "GET", "path": "/api/v1/search?q=1%27%20union%20select%20password%20from%20users--", "status_code": 500, "response_headers": {"Content-Type": "application/json"}}
{"timestamp": "2023-10-25T11:00:00Z", "source_ip": "203.0.113.5", "method": "GET", "path": "/api/v1/search?q=test%27%20UNION%20SELECT%20null--", "status_code": 200, "response_headers": {"Content-Type": "application/json", "Content-Security-Policy": "default-src 'self'", "Strict-Transport-Security": "max-age=86400"}}
EOF

    chmod -R 777 /home/user
