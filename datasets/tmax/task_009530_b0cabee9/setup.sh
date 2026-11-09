#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest flask

    cat << 'EOF' > /tmp/proxy_app.py
from flask import Flask, request, jsonify
import urllib.request
import base64

app = Flask(__name__)

@app.route('/proxy', methods=['POST'])
def proxy():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Basic '):
        return jsonify({"error": "Missing or invalid Authorization header"}), 401

    try:
        token = auth_header.split(' ')[1]
        decoded = base64.b64decode(token).decode('utf-8')
        role = decoded.split(':')[0]
        if role != 'admin':
            return jsonify({"error": "Unauthorized role. Admin required."}), 403
    except Exception:
        return jsonify({"error": "Malformed token"}), 400

    data = request.get_json()
    if not data or 'url' not in data:
        return jsonify({"error": "Missing 'url' parameter"}), 400

    url = data['url']

    # Rudimentary SSRF Filter
    blocked_terms = ['localhost', '127.0.0.1', '169.254.169.254']
    if any(term in url for term in blocked_terms):
        return jsonify({"error": "Security Policy Violation: Blocked destination."}), 403

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            content = response.read().decode('utf-8')
            return jsonify({"status": "success", "content": content}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /tmp/internal_app.py
from flask import Flask, request

app = Flask(__name__)

@app.route('/flag', methods=['GET'])
def flag():
    if request.remote_addr != '127.0.0.1':
        return "Access Denied", 403
    return "FLAG{ssrf_evasion_master_9921}"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

    # Start the services in the background so they are running during tests/usage
    nohup python3 /tmp/proxy_app.py > /dev/null 2>&1 &
    nohup python3 /tmp/internal_app.py > /dev/null 2>&1 &

    # Add to bashrc to ensure they are running when the user logs in
    echo "nohup python3 /tmp/proxy_app.py > /dev/null 2>&1 &" >> /etc/bash.bashrc
    echo "nohup python3 /tmp/internal_app.py > /dev/null 2>&1 &" >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
