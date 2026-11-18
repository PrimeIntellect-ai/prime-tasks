#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx sqlite3 curl
    pip3 install pytest flask

    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /app/nginx.conf &
python3 /app/db_writer.py &
python3 /app/ingest.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
error_log /tmp/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    access_log /tmp/access.log;

    server {
        listen 8000;
        location /submit {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /app/ingest.py
import os
import socket
from flask import Flask, request, jsonify

app = Flask(__name__)

def validate_payload(json_str):
    # Broken: always returns False
    return False

@app.route('/submit', methods=['POST'])
def submit():
    payload = request.get_data(as_text=True)
    if validate_payload(payload):
        # Broken socket logic: writes to TCP instead of UNIX socket
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(('127.0.0.1', 9999))
            s.sendall(payload.encode('utf-8'))
            s.close()
            return jsonify({"status": "success"}), 200
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500
    else:
        return jsonify({"status": "invalid"}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/db_writer.py
import socket
import os
import sqlite3
import json

DB_PATH = '/app/analytics.db'
SOCK_PATH = '/tmp/db.sock'

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS users
                 (user_id TEXT, username TEXT, email TEXT, age INTEGER, bio TEXT)''')
    conn.commit()
    conn.close()

def start_server():
    if os.path.exists(SOCK_PATH):
        os.remove(SOCK_PATH)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK_PATH)
    server.listen(5)

    while True:
        conn, addr = server.accept()
        data = conn.recv(4096)
        if data:
            try:
                payload = json.loads(data.decode('utf-8'))
                db_conn = sqlite3.connect(DB_PATH)
                c = db_conn.cursor()
                c.execute("INSERT INTO users (user_id, username, email, age, bio) VALUES (?, ?, ?, ?, ?)",
                          (payload.get('user_id'), payload.get('username'), payload.get('email'), payload.get('age'), payload.get('bio')))
                db_conn.commit()
                db_conn.close()
            except Exception as e:
                pass
        conn.close()

if __name__ == '__main__':
    init_db()
    start_server()
EOF

    python3 -c "
import json, uuid, random, os
for i in range(100):
    clean_data = {
        'user_id': str(uuid.uuid4()),
        'username': f'user{i:03d}',
        'email': f'user{i}@example.com',
        'age': random.randint(18, 120),
        'bio': 'Just a normal bio without any tags.'
    }
    with open(f'/app/corpora/clean/file_{i}.json', 'w') as f:
        json.dump(clean_data, f)

    evil_data = clean_data.copy()
    choice = i % 5
    if choice == 0:
        evil_data['user_id'] = 'not-a-uuid'
    elif choice == 1:
        evil_data['username'] = 'u'
    elif choice == 2:
        evil_data['email'] = 'not-an-email'
    elif choice == 3:
        evil_data['age'] = 17
    elif choice == 4:
        evil_data['bio'] = 'Bio with <script>alert(1)</script>'
    with open(f'/app/corpora/evil/file_{i}.json', 'w') as f:
        json.dump(evil_data, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
