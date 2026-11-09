#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat locales tzdata
    pip3 install pytest

    # Generate locale that the task expects to be used
    locale-gen en_US.UTF-8

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/releases/v1
    mkdir -p /home/user/releases/v2

    cat << 'EOF' > /home/user/releases/v1/worker.py
#!/usr/bin/env python3
import os, sys
print("v1 running")
EOF

    cat << 'EOF' > /home/user/releases/v2/worker.py
#!/usr/bin/env python3
import os, sys, datetime
tz = os.environ.get('TZ', 'UTC')
lc = os.environ.get('LC_ALL', 'C')
cwd = os.getcwd()
with open("worker_output.log", "w") as f:
    f.write(f"Version: v2\nTZ: {tz}\nLC_ALL: {lc}\nCWD: {cwd}\n")
EOF

    chmod +x /home/user/releases/v1/worker.py
    chmod +x /home/user/releases/v2/worker.py

    chmod -R 777 /home/user
