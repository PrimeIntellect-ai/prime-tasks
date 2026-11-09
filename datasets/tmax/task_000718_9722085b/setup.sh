#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/services
    mkdir -p /home/user/app_data
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/services/app_server.py
import time
import os

print("Starting app_server...")
time.sleep(3)
os.makedirs("/home/user/app_data/v1", exist_ok=True)
if not os.path.exists("/home/user/app_data/active_data"):
    os.symlink("/home/user/app_data/v1", "/home/user/app_data/active_data")
print("app_server running...")
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /home/user/services/cost_analyzer.py
import os
import sys
import time

print("Starting cost_analyzer...")
if not os.path.exists("/home/user/app_data/active_data"):
    print("FATAL: active_data missing.")
    sys.exit(1)
print("cost_analyzer running...")
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /home/user/services/start_all.sh
#!/bin/bash
python3 /home/user/services/cost_analyzer.py &
python3 /home/user/services/app_server.py &
EOF
    chmod +x /home/user/services/start_all.sh

    touch /home/user/corpus/clean/app.config
    echo "[ACTIVE] system data" > /home/user/corpus/clean/active_log.txt
    echo "Random default keep data" > /home/user/corpus/clean/random.data
    echo "" > /home/user/corpus/clean/empty.file

    touch /home/user/corpus/evil/cache.tmp
    touch /home/user/corpus/evil/old_data.bak
    echo "[ORPHANED] some forgotten bits" > /home/user/corpus/evil/lost.txt
    echo "[ORPHANED]" > /home/user/corpus/evil/short_orphan.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
