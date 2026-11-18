#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssh-client expect g++ netcat-openbsd sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Configure SSH and generate keys
    mkdir -p /var/run/sshd
    mkdir -p /home/user/.ssh
    ssh-keygen -t ed25519 -f /home/user/.ssh/id_ed25519 -N ""
    cat /home/user/.ssh/id_ed25519.pub >> /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys

    # Start SSH temporarily to get the keyscan
    service ssh start
    sleep 1
    ssh-keyscan localhost >> /home/user/.ssh/known_hosts
    service ssh stop

    chown -R user:user /home/user/.ssh

    # Create pending users file
    cat << 'EOF' > /home/user/pending_users.txt
jdoe:editor
asmith:viewer
tjones:admin
EOF

    # Create backend mock server
    cat << 'EOF' > /home/user/backend.py
import socket
import sys

HOST = '127.0.0.1'
PORT = 9999

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind((HOST, PORT))
    s.listen()
    while True:
        conn, addr = s.accept()
        with conn:
            conn.sendall(b"READY>")
            while True:
                data = conn.recv(1024)
                if not data:
                    break
                line = data.decode('utf-8').strip()
                if line == "QUIT":
                    break
                elif line.startswith("ADD_USER "):
                    with open("/home/user/server_db.log", "a") as f:
                        f.write(line + "\n")
                    conn.sendall(b"SUCCESS\nREADY>")
                else:
                    conn.sendall(b"ERROR\nREADY>")
EOF

    # Allow passwordless sudo for sshd startup if needed by the agent environment
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Ensure services are started when bash is invoked (for test environments that don't use instances)
    echo "sudo /usr/sbin/sshd 2>/dev/null || true" >> /home/user/.bashrc
    echo "pgrep -f 'python3 /home/user/backend.py' > /dev/null || python3 /home/user/backend.py &" >> /home/user/.bashrc

    chmod -R 777 /home/user
