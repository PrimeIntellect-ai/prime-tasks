#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask gunicorn redis cryptography requests

    mkdir -p /app/nginx

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /app/crypto_logger.py
import os
import hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
import json

KEY = b"S3cr3tC0mpl1anc3"

def encrypt_log(csp_report):
    timestamp = csp_report.get("timestamp", "")
    iv = hashlib.md5(timestamp.encode()).digest()
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(json.dumps(csp_report).encode()) + padder.finalize()
    cipher = Cipher(algorithms.AES(KEY), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    ct = encryptor.update(padded_data) + encryptor.finalize()
    return ct.hex()
EOF

    python3 -m py_compile /app/crypto_logger.py
    mv /app/__pycache__/crypto_logger.*.pyc /app/crypto_logger.pyc
    rm -rf /app/crypto_logger.py /app/__pycache__

    cat << 'EOF' > /app/app.py
from flask import Flask, request
import redis
import sys
import os

# Ensure we can import the pyc
sys.path.insert(0, '/app')
import crypto_logger

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/csp-report', methods=['POST'])
def csp_report():
    data = request.json
    if data:
        encrypted = crypto_logger.encrypt_log(data)
        r.lpush('csp_audit_logs', encrypted)
    return "OK", 200
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
gunicorn --bind 127.0.0.1:5000 --chdir /app app:app --daemon
nginx -c /app/nginx/nginx.conf &
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/ground_truth_payloads.json
[
    "<script>alert(1)</script>",
    "<img src=x onerror=alert(1)>",
    "javascript:alert(1)"
]
EOF

    cat << 'EOF' > /app/simulate_traffic.py
import requests
import json
import time

with open('/app/ground_truth_payloads.json', 'r') as f:
    payloads = json.load(f)

for p in payloads:
    report = {
        "timestamp": str(time.time()),
        "document-uri": "http://example.com/page?q=" + p
    }
    try:
        requests.post("http://127.0.0.1:8080/csp-report", json=report)
    except:
        pass
    time.sleep(0.01)
EOF

    cat << 'EOF' > /app/evaluate_metric.py
import json

with open('/app/ground_truth_payloads.json', 'r') as f:
    truth = json.load(f)

try:
    with open('/home/user/audit_trail.jsonl', 'r') as f:
        lines = f.readlines()
    extracted = [json.loads(l)["extracted_payload"] for l in lines]
except:
    extracted = []

correct = set(truth) & set(extracted)
if len(truth) == 0:
    f1 = 0
else:
    precision = len(correct) / len(extracted) if extracted else 0
    recall = len(correct) / len(truth)
    if precision + recall == 0:
        f1 = 0
    else:
        f1 = 2 * precision * recall / (precision + recall)

print(f"METRIC: {f1}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
