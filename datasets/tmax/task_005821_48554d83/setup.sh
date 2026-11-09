#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip iproute2
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app_storage
touch /home/user/app_storage/initial_data.bin
dd if=/dev/urandom of=/home/user/app_storage/initial_data.bin bs=1K count=1024 2>/dev/null

cat << 'EOF' > /home/user/mock_app.py
#!/usr/bin/env python3
import time
import os

print("Mock app starting...")
time.sleep(4) # Simulate slow startup
sock_path = "/home/user/app_storage/app.sock"
with open(sock_path, "w") as f:
    f.write("socket_active")

# Write some random logs to change directory size
with open("/home/user/app_storage/app.log", "w") as f:
    f.write("Log entry "*100)

print("Mock app running...")
time.sleep(15)
print("Mock app shutting down...")
if os.path.exists(sock_path):
    os.remove(sock_path)
EOF
chmod +x /home/user/mock_app.py

cat << 'EOF' > /home/user/run_all.sh
#!/bin/bash
rm -f /home/user/dashboard.json
rm -f /home/user/app_storage/app.sock
rm -f /home/user/app_storage/app.log

/home/user/mock_app.py &
APP_PID=$!

/home/user/metrics_agent.py
AGENT_EXIT=$?

wait $APP_PID
exit $AGENT_EXIT
EOF
chmod +x /home/user/run_all.sh

cat << 'EOF' > /home/user/metrics_agent.py
#!/usr/bin/env python3
import os
import sys
import json
import time
import subprocess

SOCK_PATH = "/home/user/app_storage/app.sock"
STORAGE_DIR = "/home/user/app_storage"

def check_dependency():
    # BUG: Fails immediately if the socket isn't there.
    if not os.path.exists(SOCK_PATH):
        print(f"Error: {SOCK_PATH} not found. Dependency not met!")
        sys.exit(1)
    print("Dependency met.")

def get_storage_bytes():
    # TODO: Implement total size calculation of STORAGE_DIR
    return 0

def get_default_gateway():
    # TODO: Implement parsing of 'ip route' to find the default gateway
    return "0.0.0.0"

def main():
    check_dependency()

    storage = get_storage_bytes()
    gateway = get_default_gateway()

    payload = {
        "storage_bytes": storage,
        "default_gateway": gateway,
        "status": "active"
    }

    with open("/home/user/dashboard.json", "w") as f:
        json.dump(payload, f, indent=2)
    print("Dashboard updated.")

if __name__ == "__main__":
    main()
EOF
chmod +x /home/user/metrics_agent.py

chmod -R 777 /home/user
