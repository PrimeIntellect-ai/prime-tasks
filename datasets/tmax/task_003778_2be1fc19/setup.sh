#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/writer.py
import time
import fcntl
import sys
import os

log_file = '/home/user/project/data.log'
# Ensure file exists
open(log_file, 'a').close()

i = 0
while i < 3000:
    try:
        with open(log_file, 'a') as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(f"Log entry {i}\n")
            f.flush()
            fcntl.flock(f, fcntl.LOCK_UN)
        i += 1
        time.sleep(0.01)
    except Exception as e:
        pass
EOF

    chmod +x /home/user/project/writer.py
    touch /home/user/project/data.log

    # Create a dummy pid file so it exists before the first bash run
    echo "1" > /home/user/project/writer.pid

    # Inject startup script into global bashrc so it runs when the agent/test starts
    cat << 'EOF' >> /etc/bash.bashrc
if [ ! -f /tmp/writer_started ]; then
    touch /tmp/writer_started
    python3 /home/user/project/writer.py &
    echo $! > /home/user/project/writer.pid
fi
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
