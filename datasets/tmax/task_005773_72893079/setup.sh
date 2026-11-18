#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    # Create legacy certs
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/old_key.pem -out /home/user/old_cert.pem -days 1 -nodes -subj "/CN=old-internal"

    # Create the initial app.py
    cat << 'EOF' > /home/user/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)
VALID_TOKEN = "OLD_SUPER_SECRET"

@app.route('/data')
def data():
    token = request.headers.get('Authorization')
    if token == f"Bearer {VALID_TOKEN}":
        return jsonify({"data": "secure sensitive data"}), 200
    return jsonify({"error": "Unauthorized"}), 401

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8443, ssl_context=('/home/user/old_cert.pem', '/home/user/old_key.pem'))
EOF

    chmod -R 777 /home/user
