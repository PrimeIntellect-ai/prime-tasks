#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/config
echo "cache_node 192.168.1.10 6379 memcache defaults" > /home/user/config/micro_fstab
echo "storage_node 127.0.0.1 8123 nfs ro,noauto" >> /home/user/config/micro_fstab

# Create a bash environment script to start the dummy listener for bash shells
cat << 'EOF' > /etc/bash_env.sh
python3 -c "import socket, threading; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', 8123)); s.listen(1); threading.Thread(target=lambda: s.accept(), daemon=True).start()" 2>/dev/null &
EOF
chmod +x /etc/bash_env.sh

# Create sitecustomize.py to start the dummy listener for Python invocations (like pytest)
mkdir -p /usr/lib/python3.10
cat << 'EOF' > /usr/lib/python3.10/sitecustomize.py
import socket
import threading

def start_listener():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', 8123))
        s.listen(1)
        def accept_conn():
            try:
                conn, addr = s.accept()
                conn.close()
            except:
                pass
        t = threading.Thread(target=accept_conn)
        t.daemon = True
        t.start()
    except Exception:
        pass

start_listener()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
