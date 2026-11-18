#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/db.py
import time, sys
time.sleep(1)
print("SYSTEM_READY")
sys.stdout.flush()
time.sleep(10)
EOF

    cat << 'EOF' > /home/user/app.py
import sys, os
state_file = "/home/user/app.state"
if not os.path.exists(state_file):
    count = 0
else:
    with open(state_file, "r") as sf:
        count = int(sf.read().strip())
count += 1
with open(state_file, "w") as sf:
    sf.write(str(count))

if count <= 2:
    sys.exit(1)
else:
    sys.exit(0)
EOF

    cat << 'EOF' > /home/user/manifest.json
{
  "services": {
    "db": {
      "command": "/usr/bin/python3 /home/user/db.py",
      "ready_marker": "SYSTEM_READY"
    },
    "app": {
      "command": "/usr/bin/python3 /home/user/app.py",
      "depends_on": "db",
      "restart_policy": "Always",
      "max_restarts": 3
    }
  }
}
EOF

    chmod 755 /home/user/db.py
    chmod 755 /home/user/app.py
    chmod -R 777 /home/user
