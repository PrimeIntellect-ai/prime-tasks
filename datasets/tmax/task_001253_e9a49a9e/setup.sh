#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    mkdir -p /app/services/log-ingest
    mkdir -p /app/services/legacy-auth

    # Create legacy-auth
    cat << 'EOF' > /app/services/legacy-auth/auth_token.py
def get_admin_cookie():
    return "admin_cookie_v1_S3cr3t"

def encrypt(text):
    key = "S3cr3t"
    return "".join(f"{ord(c) ^ ord(key[i % len(key)]):02X}" for i, c in enumerate(text))

def decrypt(hex_text):
    key = "S3cr3t"
    chars = [chr(int(hex_text[i:i+2], 16)) for i in range(0, len(hex_text), 2)]
    return "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(chars))
EOF

    python3 -m py_compile /app/services/legacy-auth/auth_token.py
    mv /app/services/legacy-auth/__pycache__/auth_token.*.pyc /app/services/legacy-auth/auth_token.pyc
    rm -rf /app/services/legacy-auth/auth_token.py /app/services/legacy-auth/__pycache__

    # Create log-ingest app
    cat << 'EOF' > /app/services/log-ingest/app.py
from flask import Flask, request, jsonify
import sqlite3
import os

app = Flask(__name__)

def get_db():
    conn = sqlite3.connect('/app/services/log-ingest/logs.db')
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.execute('CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, user TEXT, action TEXT)')
    cursor = conn.cursor()
    cursor.execute('SELECT count(*) FROM logs')
    if cursor.fetchone()[0] == 0:
        def encrypt(text):
            key = "S3cr3t"
            return "".join(f"{ord(c) ^ ord(key[i % len(key)]):02X}" for i, c in enumerate(text))
        conn.execute("INSERT INTO logs (id, user, action) VALUES (1, ?, ?)", (encrypt("admin"), encrypt("login")))
    conn.commit()

@app.route('/search')
def search():
    user = request.args.get('user', '')
    conn = get_db()
    cursor = conn.cursor()
    query = f"SELECT * FROM logs WHERE user = '{user}'"
    try:
        cursor.execute(query)
        rows = cursor.fetchall()
        return jsonify([dict(r) for r in rows])
    except Exception as e:
        return str(e), 500

@app.route('/export')
def export():
    cookie = request.cookies.get('admin_session')
    if cookie != "admin_cookie_v1_S3cr3t":
        return "Unauthorized", 401
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM logs")
    rows = cursor.fetchall()
    return jsonify([dict(r) for r in rows])

if __name__ == '__main__':
    init_db()
    app.run(host='127.0.0.1', port=5002)
EOF

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
python3 /app/services/log-ingest/app.py &
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
