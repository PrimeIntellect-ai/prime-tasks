#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis

    # Create directories
    mkdir -p /home/user/waf
    mkdir -p /home/user/nginx
    mkdir -p /home/user/api
    mkdir -p /home/user/logs
    mkdir -p /home/user/data
    mkdir -p /home/user/test_data

    # Create files
    echo '[]' > /home/user/test_data/evil_tokens.json
    echo '[]' > /home/user/test_data/clean_tokens.json

    # Create issuer hashes
    echo -n "trusted-corp.com" | sha256sum | awk '{print $1}' > /home/user/data/valid_issuers.sha256
    echo -n "internal-auth.net" | sha256sum | awk '{print $1}' >> /home/user/data/valid_issuers.sha256

    # Create basic Flask app scaffold
    cat << 'EOF' > /home/user/api/app.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/api/data', methods=['GET'])
def get_data():
    return jsonify({"status": "success", "data": "dummy"}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
