#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/backup /home/user/data/active /home/user/run

# Create the config file and back it up
cd /home/user/backup
echo '{"metrics_interval": 5, "debug": true}' > config.json
tar -czf metrics_backup.tar.gz config.json
rm config.json
cd /home/user

# Create metrics-gatherer.py
cat << 'EOF' > /home/user/metrics-gatherer.py
#!/usr/bin/env python3
import os
import time
import sys

config_path = '/home/user/data/active/config.json'
sock_path = '/home/user/data/active/metrics.sock'

if not os.path.exists(config_path):
    print("FATAL: config.json missing. Startup failed.")
    sys.exit(1)

time.sleep(2) # Simulate startup delay
with open(sock_path, 'w') as f:
    f.write("mock_socket_active")

while True:
    time.sleep(10)
EOF
chmod +x /home/user/metrics-gatherer.py

# Create dashboard-backend.py
cat << 'EOF' > /home/user/dashboard-backend.py
#!/usr/bin/env python3
import os
import time
import sys

sock_path = '/home/user/data/active/metrics.sock'

if not os.path.exists(sock_path):
    print("FATAL: metrics.sock missing. Gatherer not ready.")
    sys.exit(1)

while True:
    time.sleep(10)
EOF
chmod +x /home/user/dashboard-backend.py

chmod -R 777 /home/user
