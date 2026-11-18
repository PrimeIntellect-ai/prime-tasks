#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect netcat-openbsd
pip3 install pytest

mkdir -p /home/user/sysfiles

cat << 'EOF' > /home/user/sysfiles/group
root:x:0:
admin:x:1001:alice,bob
users:x:100:
dev:x:1002:charlie
EOF

cat << 'EOF' > /home/user/sysfiles/passwd
root:x:0:0:root:/root:/bin/bash
alice:x:1001:100:Alice:/home/alice:/bin/bash
bob:x:1002:100:Bob:/home/bob:/bin/bash
charlie:x:1003:1001:Charlie:/home/charlie:/bin/bash
dave:x:1004:100:Dave:/home/dave:/bin/bash
EOF

cat << 'EOF' > /home/user/legacy_service.py
#!/usr/bin/env python3
import socket
import sys

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8888))
    s.listen(1)
    conn, addr = s.accept()
    try:
        conn.sendall(b"Username: ")
        data = conn.recv(1024)
        if data.strip() != b"admin":
            conn.sendall(b"Access Denied\n")
            return
        conn.sendall(b"Password: ")
        data = conn.recv(1024)
        if data.strip() != b"supersecret":
            conn.sendall(b"Access Denied\n")
            return
        conn.sendall(b"Access Granted\n")
    finally:
        conn.close()
        s.close()

if __name__ == "__main__":
    main()
EOF

chmod +x /home/user/legacy_service.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
