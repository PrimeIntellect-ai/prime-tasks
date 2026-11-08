#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the dummy VNC service script
    cat << 'EOF' > /usr/local/bin/dummy_vnc.py
import socket
import time
import sys

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(('127.0.0.1', 5900))
        s.listen(5)
    except Exception as e:
        sys.exit(1)

    while True:
        try:
            conn, addr = s.accept()
            conn.close()
        except Exception:
            time.sleep(0.1)

if __name__ == "__main__":
    main()
EOF

    # Use sitecustomize.py to ensure the dummy service is running when Python starts
    cat << 'EOF' > /usr/lib/python3.10/sitecustomize.py
import os
import subprocess
import socket

def start_dummy_vnc():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.1)
    result = s.connect_ex(('127.0.0.1', 5900))
    s.close()

    if result != 0:
        try:
            with open(os.devnull, 'w') as devnull:
                subprocess.Popen(['python3', '/usr/local/bin/dummy_vnc.py'], stdout=devnull, stderr=devnull)
        except Exception:
            pass

start_dummy_vnc()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
