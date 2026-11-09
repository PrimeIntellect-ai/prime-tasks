#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    # Create the flag file
    echo "FLAG{obfuscation_and_evasion_master}" > /home/user/flag.txt
    chmod 400 /home/user/flag.txt
    chown user:user /home/user/flag.txt

    # Create the vulnerable service
    cat << 'EOF' > /home/user/target_app.py
from flask import Flask, request, jsonify
import hashlib
import traceback

app = Flask(__name__)

BLOCKED_WORDS = ['os', 'system', 'subprocess', 'open', 'read', 'import', 'eval', 'exec', 'flag']

@app.route('/login', methods=['GET', 'POST'])
def login():
    token = request.headers.get('X-Auth-Token', '')
    payload_hash = request.headers.get('X-Payload-Hash', '')

    if not token:
        return jsonify({"error": "Missing X-Auth-Token header"}), 400

    # 1. Checksum Verification
    expected_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()
    if payload_hash != expected_hash:
        return jsonify({"error": "Checksum verification failed"}), 400

    # 2. WAF Simulation
    for word in BLOCKED_WORDS:
        if word in token:
            return jsonify({"error": f"WAF Blocked: malicious string detected"}), 403

    # 3. Vulnerable Evaluation
    try:
        # Evaluate the token
        result = eval(token)
        return jsonify({"message": "Authentication processed", "result": str(result)}), 200
    except Exception as e:
        return jsonify({"error": "Evaluation error", "details": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    chmod 755 /home/user/target_app.py
    chown user:user /home/user/target_app.py

    # Ensure the service starts when a shell is opened (fallback for testing)
    echo 'ps aux | grep -q "[t]arget_app.py" || nohup python3 /home/user/target_app.py > /dev/null 2>&1 &' >> /home/user/.bashrc
    echo 'ps aux | grep -q "[t]arget_app.py" || nohup python3 /home/user/target_app.py > /dev/null 2>&1 &' >> /root/.bashrc

    chmod -R 777 /home/user
    # Re-apply strict permissions for the flag after the recursive chmod
    chmod 400 /home/user/flag.txt
