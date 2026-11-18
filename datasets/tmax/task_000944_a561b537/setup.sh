#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Flask

    mkdir -p /app/vendored/py-state-manager-1.0.0

    cat << 'EOF' > /app/vendored/py-state-manager-1.0.0/app.py
import os
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

storage_dir = os.environ.get('STORAG_DIR', './default_data')
try:
    os.makedirs(storage_dir, exist_ok=True)
except Exception:
    pass
state_file = os.path.join(storage_dir, 'state.json')

AUTH_TOKEN = os.environ.get('AUTH_TOKEN', '')

@app.before_request
def check_auth():
    auth_header = request.headers.get('Authorization')
    if auth_header != f"Bearer {AUTH_TOKEN}":
        return jsonify({"error": "Unauthorized"}), 401

@app.route('/write', methods=['POST'])
def write_state():
    data = request.json
    try:
        if not os.path.exists(storage_dir):
            os.makedirs(storage_dir, exist_ok=True)
        with open(state_file, 'w') as f:
            json.dump(data, f)
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/read', methods=['GET'])
def read_state():
    if not os.path.exists(state_file):
        return jsonify({}), 200
    try:
        with open(state_file, 'r') as f:
            data = json.load(f)
        return jsonify(data), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    host = os.environ.get('HOST', '127.0.0.1')
    port = int(os.environ.get('PORT', 9090))
    app.run(host=host, port=port)
EOF

    cat << 'EOF' > /app/vendored/py-state-manager-1.0.0/run.sh
#!/bin/bash
export STORAG_DIR=/tmp/bad_path
python3 app.py
EOF

    chmod +x /app/vendored/py-state-manager-1.0.0/run.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
