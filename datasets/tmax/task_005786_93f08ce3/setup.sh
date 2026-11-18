#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/manifests/available

    cat << 'EOF' > /home/user/manifests/available/app1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
EOF

    cat << 'EOF' > /home/user/manifests/available/app2.yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
EOF

    cat << 'EOF' > /home/user/manifests/available/app3.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
EOF

    cat << 'EOF' > /home/user/setup_wizard.sh
#!/bin/bash
read -p "Enter environment: " env_name
read -p "Enter manifest dir: " man_dir

if [ "$env_name" == "production" ] && [ "$man_dir" == "/home/user/manifests/active" ]; then
    echo "env=$env_name" > /home/user/operator.conf
    echo "dir=$man_dir" >> /home/user/operator.conf
    echo "Configuration saved."
else
    echo "Invalid input."
    exit 1
fi
EOF
    chmod +x /home/user/setup_wizard.sh

    cat << 'EOF' > /home/user/services.json
{
  "validator": {
    "command": "echo 'Validator started'"
  },
  "operator": {
    "command": "echo 'Operator started'"
  }
}
EOF

    cat << 'EOF' > /home/user/runner.py
#!/usr/bin/env python3
import json
import os

if not os.path.exists('/home/user/operator.conf'):
    print("Missing operator.conf")
    exit(1)

with open('/home/user/services.json', 'r') as f:
    services = json.load(f)

operator_conf = services.get('operator', {})
if operator_conf.get('depends_on') != 'validator':
    print("Operator failed to start: validator not running.")
    exit(1)

active_dir = '/home/user/manifests/active'
if not os.path.exists(active_dir):
    print("Active directory missing")
    exit(1)

links = os.listdir(active_dir)
if sorted(links) != ['app1.yaml', 'app3.yaml']:
    print("Incorrect symlinks in active directory")
    exit(1)

for link in links:
    if not os.path.islink(os.path.join(active_dir, link)):
        print(f"{link} is not a symlink")
        exit(1)

with open('/home/user/operator_success.log', 'w') as f:
    f.write("All systems nominal.\n")
print("Runner completed successfully.")
EOF
    chmod +x /home/user/runner.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
