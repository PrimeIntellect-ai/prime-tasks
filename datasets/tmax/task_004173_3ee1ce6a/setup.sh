#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/legacy
cat << 'EOF' > /home/user/legacy/app.conf
[database]
host = db.local
port = 3306
user = admin

[cache]
host = redis.local
port = 6379
EOF

# Use sitecustomize.py to ensure mock services run automatically in the background
# whenever Python is invoked (e.g., during pytest or agent scripts)
cat << 'EOF' > /usr/lib/python3.10/sitecustomize.py
import socket
import threading

def serve(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(('localhost', port))
        s.listen(1)
        while True:
            try:
                conn, addr = s.accept()
                conn.close()
            except:
                pass
    except Exception:
        pass

threading.Thread(target=serve, args=(33060,), daemon=True).start()
threading.Thread(target=serve, args=(63790,), daemon=True).start()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
