#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/auth_service.py
import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--user", required=True)
parser.add_argument("--password", required=False) # Changed to false for agent to fix
args = parser.parse_args()

# In secure version, it should use an environment variable
password = args.password
if password == "secret":
    print("Success")
else:
    print("Failure")
EOF

    cat << 'EOF' > /home/user/run_auth.sh
#!/bin/bash
python3 /home/user/auth_service.py --user "$1" --password "$2"
EOF
    chmod +x /home/user/run_auth.sh

    cat << 'EOF' > /home/user/traffic.log
{"timestamp": 100, "ip": "192.168.1.10", "user": "admin", "status": "failed"}
{"timestamp": 101, "ip": "192.168.1.10", "user": "admin", "status": "failed"}
{"timestamp": 102, "ip": "192.168.1.10", "user": "admin", "status": "success"}
{"timestamp": 103, "ip": "192.168.1.10", "user": "admin", "status": "failed"}
{"timestamp": 104, "ip": "192.168.1.20", "user": "root", "status": "failed"}
{"timestamp": 105, "ip": "192.168.1.20", "user": "root", "status": "failed"}
{"timestamp": 106, "ip": "192.168.1.20", "user": "root", "status": "failed"}
{"timestamp": 107, "ip": "10.0.0.5", "user": "guest", "status": "failed"}
{"timestamp": 108, "ip": "10.0.0.5", "user": "guest", "status": "failed"}
{"timestamp": 109, "ip": "10.0.0.5", "user": "admin", "status": "failed"}
{"timestamp": 110, "ip": "10.0.0.5", "user": "guest", "status": "failed"}
{"timestamp": 111, "ip": "172.16.0.2", "user": "admin", "status": "failed"}
{"timestamp": 112, "ip": "172.16.0.2", "user": "admin", "status": "failed"}
{"timestamp": 113, "ip": "172.16.0.2", "user": "admin", "status": "failed"}
{"timestamp": 114, "ip": "172.16.0.2", "user": "admin", "status": "failed"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
