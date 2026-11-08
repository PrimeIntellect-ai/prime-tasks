#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deployment.json
{
  "services": {
    "cache": {
      "command": "echo 'Starting cache' && touch /home/user/cache.sock",
      "restart_policy": "on-failure"
    },
    "backend": {
      "command": "cat /home/user/cache.sock && echo 'Backend up'",
      "restart_policy": "on-failure"
    },
    "frontend": {
      "command": "echo 'Frontend up'",
      "restart_policy": "none"
    }
  }
}
EOF

    cat << 'EOF' > /home/user/deploy_runner.py
import json
import sys
import os

config_path = '/home/user/deployment.json'
group_path = '/home/user/mock_group'

if not os.path.exists(group_path):
    print("Error: mock_group file missing.")
    sys.exit(1)

with open(group_path, 'r') as f:
    if 'deploy_admins:x:1001:app_runner' not in f.read():
        print("Error: deploy_admins group missing or malformed.")
        sys.exit(1)

with open(config_path, 'r') as f:
    config = json.load(f)

backend = config['services'].get('backend', {})
if 'cache' not in backend.get('depends_on', []):
    print("Error: backend started before cache and crashed.")
    sys.exit(1)

frontend = config['services'].get('frontend', {})
if frontend.get('restart_policy') != 'always':
    print("Error: frontend restart policy is incorrect.")
    sys.exit(1)

print("Deployment Successful: All services started in the correct order.")
sys.exit(0)
EOF

    chmod -R 777 /home/user
