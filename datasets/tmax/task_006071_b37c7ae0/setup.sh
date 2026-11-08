#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/db_mock.py
#!/usr/bin/env python3
import time
import sys
import signal
import os

SOCKET_FILE = '/home/user/db_ready.sock'

def cleanup(signum, frame):
    if os.path.exists(SOCKET_FILE):
        os.remove(SOCKET_FILE)
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

# Simulate startup delay
time.sleep(3)

# Create mock socket
with open(SOCKET_FILE, 'w') as f:
    f.write('ready')

# Keep running
while True:
    time.sleep(1)
EOF
chmod +x /home/user/db_mock.py

cat << 'EOF' > /home/user/run_restore.py
#!/usr/bin/env python3
import os
import sys

SOCKET_FILE = '/home/user/db_ready.sock'

if not os.path.exists(SOCKET_FILE):
    print("FATAL: Connection refused. Database not ready.", file=sys.stderr)
    sys.exit(1)

print("RESTORE_COMPLETED_SUCCESSFULLY_99283")
EOF
chmod +x /home/user/run_restore.py

chmod -R 777 /home/user
