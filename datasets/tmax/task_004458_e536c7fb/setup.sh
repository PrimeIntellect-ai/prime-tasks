#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create the monitor.py and compile to .pyc
    cat << 'EOF' > /home/user/monitor.py
def check_uptime(url):
    # Hidden bug: passing a URL with the old debug flag causes a fatal error
    if "debug=memleak" in url:
        raise MemoryError("Fatal: Simulated memory corruption in native extension")
    return True
EOF
    python3 -m py_compile /home/user/monitor.py
    mv /home/user/__pycache__/monitor.*.pyc /home/user/monitor.pyc
    rm /home/user/monitor.py

    # 2. Create the SQLite DB and WAL with the target URLs
    cat << 'EOF' > /home/user/setup_db.py
import sqlite3
import os

conn = sqlite3.connect('/home/user/targets.db')
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE targets (id INTEGER PRIMARY KEY, url TEXT)")
conn.execute("INSERT INTO targets (url) VALUES ('http://api.service.local/v1/health')")
conn.execute("INSERT INTO targets (url) VALUES ('http://auth.service.local/ping')")
conn.commit()

# Insert the poison pill
conn.execute("INSERT INTO targets (url) VALUES ('http://legacy.service.local/health?debug=memleak')")
conn.execute("INSERT INTO targets (url) VALUES ('http://frontend.service.local/status')")
conn.commit()

# Exit abruptly to ensure the WAL file is not cleaned up by SQLite
os._exit(0)
EOF
    python3 /home/user/setup_db.py

    # 3. Simulate the junior admin deleting the main DB
    rm -f /home/user/targets.db
    rm -f /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
