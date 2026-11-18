#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/sequence_worker.py
import time, sys
f = open("/home/user/config_multiplier.txt", "r")
multiplier = int(f.read().strip())
log = open("/home/user/sequence_trace.log", "w")

for i in range(1, 75):
    log.write(f"STARTING Sequence_ID {i}\n")
    log.flush()
    if i == 74:
        while True:
            time.sleep(1)
    log.write(f"COMPLETED Sequence_ID {i}\n")
    log.flush()
EOF

cat << 'EOF' > /.singularity.d/env/99-setup.sh
if ! pgrep -f sequence_worker.py > /dev/null; then
    echo "4285" > /home/user/config_multiplier.txt
    nohup python3 /home/user/sequence_worker.py > /dev/null 2>&1 &
    sleep 2
    rm -f /home/user/config_multiplier.txt
fi
EOF

chmod -R 777 /home/user
