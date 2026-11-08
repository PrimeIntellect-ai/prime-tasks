#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_target
    cd /home/user/audit_target

    cat << 'EOF' > app.py
import sqlite3
from flask import Flask, request, jsonify

app = Flask(__name__)
DB_PATH = '/home/user/audit_target/users.db'

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/user')
def get_user():
    user_id = request.args.get('id')
    conn = get_db_connection()
    cursor = conn.cursor()
    # Vulnerable SQLi query
    query = f"SELECT * FROM users WHERE id = {user_id}"
    cursor.execute(query)
    user = cursor.fetchone()
    conn.close()
    if user:
        return jsonify(dict(user))
    return jsonify({"error": "Not found"}), 404

@app.route('/greet')
def greet():
    name = request.args.get('name', 'Guest')
    # Vulnerable XSS response
    return f"<html><body><h1>Hello, {name}!</h1></body></html>"

if __name__ == '__main__':
    # Application binds here
    app.run(host='0.0.0.0', port=8443)
EOF

    echo "secret_key = 'super_secret'" > config.ini
    touch users.db

    chmod -R 777 /home/user

    # Fix permissions so tests pass
    chmod 644 /home/user/audit_target/app.py
    chmod 644 /home/user/audit_target/config.ini
    chmod 666 /home/user/audit_target/users.db
