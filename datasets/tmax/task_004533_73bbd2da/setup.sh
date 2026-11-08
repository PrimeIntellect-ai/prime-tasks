#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest flask requests

    mkdir -p /home/user/app
    mkdir -p /app

    cat << 'EOF' > /home/user/app/config.json
{
    "api_host": "127.0.0.1",
    "api_port": 80
}
EOF

    cat << 'EOF' > /home/user/app/frontend.py
import json
import requests
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/status')
def status():
    try:
        with open('/home/user/app/config.json', 'r') as f:
            config = json.load(f)
        port = config.get('api_port', 80)
        host = config.get('api_host', '127.0.0.1')
        r = requests.get(f"http://{host}:{port}/status", timeout=1)
        if r.status_code == 200 and r.json().get('status') == 'ok':
            return jsonify({"status": "ok", "api_connected": True})
    except Exception as e:
        pass
    return jsonify({"status": "error", "api_connected": False})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    cat << 'EOF' > /home/user/app/backend.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/status')
def status():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
cd /home/user/app
nohup python3 backend.py > backend.log 2>&1 &
nohup python3 frontend.py > frontend.log 2>&1 &
EOF
    chmod +x /home/user/app/start.sh

    cat << 'EOF' > /app/oracle_packet_parser.py
#!/usr/bin/env python3
import sys

def parse():
    line = sys.stdin.read().strip()
    if not line:
        return
    if len(line) < 14:
        print("INVALID_HEADER")
        return

    try:
        version = int(line[0:2], 16)
        length = int(line[2:6], 16)
        timestamp = int(line[6:14], 16)
        payload_hex = line[14:]
    except ValueError:
        return

    actual_length = 7 + len(payload_hex) // 2
    if length != actual_length:
        print("LENGTH_MISMATCH")
        return

    payload_ascii = ""
    for i in range(0, len(payload_hex), 2):
        byte_val = int(payload_hex[i:i+2], 16)
        if 32 <= byte_val <= 126:
            payload_ascii += chr(byte_val)
        else:
            payload_ascii += "."

    print(f"V:{version} LEN:{length} TS:{timestamp} DATA:{payload_ascii}")

if __name__ == "__main__":
    parse()
EOF
    chmod +x /app/oracle_packet_parser.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
