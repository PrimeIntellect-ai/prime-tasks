#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDF1111 user1@host
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCxyz22 user2@host
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQBadKey user3@host
EOF

    cat << 'EOF' > /home/user/compromised.txt
5032dfa7c73db2ba9b8eec8746fb94ba20141d6db2f51f4c7d0d01d4a07018c1
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF

    cat << 'EOF' > /home/user/server.py
import socket
import base64

def run_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8005))
    s.listen(1)
    while True:
        conn, addr = s.accept()
        data = conn.recv(1024)
        if b'U0NBTl9DT01NQU5E' in data:
            secret = b"FLAG_7b_vulnerable_service_found_7d"
            resp = base64.b64encode(secret) + b"\n"
            conn.sendall(resp)
        conn.close()

if __name__ == '__main__':
    run_server()
EOF

    # Ensure the background server starts when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-start-server.sh
if ! pgrep -f "python3 /home/user/server.py" > /dev/null 2>&1; then
    python3 /home/user/server.py > /dev/null 2>&1 &
    sleep 0.5
fi
EOF

    chmod -R 777 /home/user
