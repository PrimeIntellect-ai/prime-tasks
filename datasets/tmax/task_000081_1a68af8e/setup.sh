#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask

    mkdir -p /app
    mkdir -p /var/uploads

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        # location /api/ {
        #     proxy_pass http://127.0.0.1:5000/;
        # }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    return jsonify({"message": "Upload successful"})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx.conf
python3 /app/app.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/oracle_auditor
#!/usr/bin/env python3
import sys
import json
import base64
import os
import hashlib

def process_line(line):
    try:
        data = json.loads(line)
        filename = data.get("filename", "")
        payload_b64 = data.get("payload_b64", "")

        base_dir = "/var/uploads"
        joined = os.path.join(base_dir, filename)
        canonical_path = os.path.abspath(joined)

        status = "clean"
        sha256_hash = None

        try:
            payload = base64.b64decode(payload_b64, validate=True)
        except Exception:
            status = "error"
            payload = None

        if status != "error":
            if not canonical_path.startswith(base_dir + "/") and canonical_path != base_dir:
                status = "malicious"
            elif b"\xDE\xAD\xBE\xEF" in payload:
                status = "malicious"

        if status == "clean":
            sha256_hash = hashlib.sha256(payload).hexdigest()

        return json.dumps({
            "status": status,
            "canonical_path": canonical_path,
            "sha256": sha256_hash
        })
    except Exception:
        pass

if __name__ == "__main__":
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        print(process_line(line))
EOF
    chmod +x /app/oracle_auditor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/uploads
