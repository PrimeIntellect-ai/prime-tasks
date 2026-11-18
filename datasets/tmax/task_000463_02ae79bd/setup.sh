#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect netcat-openbsd curl
    pip3 install pytest flask

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/incoming_mail
    mkdir -p /app

    # Create clean corpus
    cat << 'EOF' > /home/user/corpora/clean/1.eml
Subject: [ALERT] memory_usage
Date: Thu, 21 Dec 2023 15:00:00 +0200
From: system@legacy

Value: 95.5
EOF

    # Create evil corpus
    cat << 'EOF' > /home/user/corpora/evil/1.eml
Subject: [ALERT] memory_usage
Date: Thu, 21 Dec 2023 15:00:00 +0200
From: system@legacy

Value: notafloat
EOF

    # Create legacy emitter
    cat << 'EOF' > /app/legacy_emitter.py
import socket
import threading
import email.utils
import time

def handle_client(conn):
    try:
        conn.sendall(b"Username: ")
        user = conn.recv(1024).decode().strip()
        conn.sendall(b"Password: ")
        pw = conn.recv(1024).decode().strip()
        conn.sendall(b"Locale: ")
        loc = conn.recv(1024).decode().strip()
        conn.sendall(b"Timezone: ")
        tz = conn.recv(1024).decode().strip()

        while True:
            conn.sendall(b"> ")
            cmd = conn.recv(1024).decode().strip()
            if cmd.startswith("EMIT "):
                parts = cmd.split()
                if len(parts) >= 3:
                    metric = parts[1]
                    val = parts[2]
                    date_str = email.utils.formatdate(time.time(), localtime=False)
                    filename = f"/home/user/incoming_mail/{time.time()}.eml"
                    with open(filename, "w") as f:
                        f.write(f"Subject: [ALERT] {metric}\nDate: {date_str}\n\nValue: {val}\n")
            elif cmd == "QUIT":
                break
    except Exception as e:
        pass
    finally:
        conn.close()

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 10023))
s.listen(5)
while True:
    conn, addr = s.accept()
    threading.Thread(target=handle_client, args=(conn,)).start()
EOF

    # Create dashboard API
    cat << 'EOF' > /app/dashboard_api.py
from flask import Flask, request
import json

app = Flask(__name__)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    with open('/home/user/dashboard_db.json', 'w') as f:
        json.dump(data, f)
    return "OK"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=10080)
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/legacy_emitter.py &
python3 /app/dashboard_api.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
