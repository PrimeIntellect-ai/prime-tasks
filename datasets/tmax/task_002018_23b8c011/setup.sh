#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl tar sed
    pip3 install pytest

    mkdir -p /home/user/app/services/logs
    mkdir -p /home/user/app/urllib3-src

    # Download urllib3 1.26.12
    curl -sL https://github.com/urllib3/urllib3/archive/refs/tags/1.26.12.tar.gz | tar -xz -C /home/user/app/urllib3-src --strip-components=1

    # Inject perturbation
    sed -i '/def connect(self):/a \        if self.host == "127.0.0.2":\n            import time\n            time.sleep(0.5)' /home/user/app/urllib3-src/src/urllib3/connection.py

    # Setup venv
    python3 -m venv /home/user/app/venv
    /home/user/app/venv/bin/pip install flask
    /home/user/app/venv/bin/pip install -e /home/user/app/urllib3-src

    # Create services
    cat << 'EOF' > /home/user/app/services/user_db_service.py
from flask import Flask
app = Flask(__name__)

@app.route('/sync')
def sync():
    return "ok"

if __name__ == '__main__':
    app.run(host='127.0.0.2', port=8080)
EOF

    cat << 'EOF' > /home/user/app/services/sync_worker.py
import urllib3

def do_sync():
    http = urllib3.PoolManager()
    r = http.request('GET', 'http://127.0.0.2:8080/sync')
    return r.status == 200

if __name__ == '__main__':
    do_sync()
EOF

    cat << 'EOF' > /home/user/verifier_benchmark.py
import sys
import time
import subprocess

# Ensure DB service is running
db_proc = subprocess.Popen(["/home/user/app/venv/bin/python", "/home/user/app/services/user_db_service.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1) # wait for startup

sys.path.insert(0, '/home/user/app/services')
import sync_worker

try:
    start = time.time()
    for _ in range(20):
        sync_worker.do_sync()
    end = time.time()
    print(end - start)
finally:
    db_proc.terminate()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
