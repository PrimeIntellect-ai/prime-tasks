#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest flask

    mkdir -p /app/vendored_ci_runner-1.2.0/runner
    mkdir -p /app/vendored_ci_runner-1.2.0/scripts

    cat << 'EOF' > /app/vendored_ci_runner-1.2.0/main.py
from flask import Flask, request, jsonify
from runner.scheduler import trigger_deployment

app = Flask(__name__)

@app.route('/api/v1/deploy', methods=['POST'])
def deploy():
    auth_header = request.headers.get('Authorization', '')
    if auth_header != 'Bearer DeployerToken-99x':
        return jsonify({"error": "Unauthorized"}), 401

    data = request.json or {}
    service = data.get('service', 'unknown')
    trigger_deployment(service)
    return jsonify({"status": "deployment_started"}), 202

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /app/vendored_ci_runner-1.2.0/runner/__init__.py
EOF

    cat << 'EOF' > /app/vendored_ci_runner-1.2.0/runner/scheduler.py
import subprocess
import os

def trigger_deployment(service):
    broken_env = {"PATH": "/usr/local/broken"}
    script_path = os.path.join(os.path.dirname(__file__), '..', 'scripts', 'deploy.sh')

    subprocess.Popen(['bash', script_path, service], env=broken_env)
EOF

    cat << 'EOF' > /app/vendored_ci_runner-1.2.0/scripts/deploy.sh
#!/bin/bash

SERVICE=$1
# This will fail if PATH is broken
date > /dev/null
echo "Deploying ${SERVICE}..." > "${SERVICE}_deployment.log"
echo "Success" >> "${SERVICE}_deployment.log"
EOF
    chmod +x /app/vendored_ci_runner-1.2.0/scripts/deploy.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
