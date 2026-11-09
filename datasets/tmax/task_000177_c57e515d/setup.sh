#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server iptables curl jq
    pip3 install pytest flask

    mkdir -p /app/corpus/clean /app/corpus/evil /app/testbed

    cat << 'EOF' > /app/dropper.py
import base64
import hashlib

def decode_payload(payload_b64, expected_checksum):
    decoded_bytes = base64.b64decode(payload_b64)
    xored = bytearray()
    for b in decoded_bytes:
        xored.append(b ^ 0x5A)

    decoded_str = xored.decode('utf-8')
    md5 = hashlib.md5(decoded_str.encode('utf-8')).hexdigest()

    if md5 != expected_checksum:
        raise ValueError("Checksum mismatch")

    if "__import__" in decoded_str or "redis.call" in decoded_str:
        return "MALICIOUS"
    return "SAFE"
EOF
    python3 -m py_compile /app/dropper.py
    mv /app/__pycache__/dropper*.pyc /app/dropper.pyc
    rm -rf /app/__pycache__ /app/dropper.py

    cat << 'EOF' > /app/corpus/clean/req1.json
{"payload": "Mj80Nw==", "checksum": "8c4205ec33d8f6caeaaaa0c10a14138c"}
EOF

    cat << 'EOF' > /app/corpus/evil/req1.json
{"payload": "eHxfXX19X3xcWnxfXCgnfHp8Jyk=", "checksum": "0db848ff791ab1a179c3cf85284eb961"}
EOF

    cat << 'EOF' > /app/testbed/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/testbed/app.py
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route('/', methods=['POST'])
def handle():
    return jsonify({"status": "success"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/testbed/start.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/testbed/app.py &
nginx -c /app/testbed/nginx.conf &
EOF
    chmod +x /app/testbed/start.sh

    cat << 'EOF' > /app/evaluate_waf.sh
#!/bin/bash
# Evaluates the WAF
EOF
    chmod +x /app/evaluate_waf.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
