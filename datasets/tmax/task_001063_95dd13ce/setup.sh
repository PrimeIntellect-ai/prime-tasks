#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server
    pip3 install pytest

    # Configure SSH to allow connections despite 777 permissions on home directory
    echo "StrictModes no" >> /etc/ssh/sshd_config
    mkdir -p /run/sshd
    chmod 755 /run/sshd

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup SSH keys
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys

    # Setup app directory and files
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/db_service.py
import time, socket
print("DB initializing...")
time.sleep(5)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 8001))
s.listen(1)
print("DB ready on 8001")
while True:
    conn, addr = s.accept()
    conn.close()
EOF

    cat << 'EOF' > /home/user/app/api_service.py
import socket, sys, time
try:
    s = socket.create_connection(('127.0.0.1', 8001), timeout=1)
    s.close()
except Exception:
    print("API FATAL: DB not reachable on 8001")
    sys.exit(1)

print("API connected to DB. Starting API...")
s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s2.bind(('127.0.0.1', 8002))
s2.listen(1)
print("API ready on 8002")
while True:
    conn, addr = s2.accept()
    conn.sendall(b"API_OK")
    conn.close()
EOF

    cat << 'EOF' > /home/user/app/monitor_service.py
import socket, sys, time
try:
    s = socket.create_connection(('127.0.0.1', 9000), timeout=2)
    data = s.recv(1024)
    s.close()
    if b"API_OK" in data:
        with open("/home/user/app/monitor.log", "w") as f:
            f.write("STATUS: ALL_SYSTEMS_GO\n")
        print("Monitor success.")
    else:
        sys.exit(1)
except Exception as e:
    print(f"Monitor failed: {e}")
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/app/start_all.py
import subprocess, time
print("Starting all services...")
db = subprocess.Popen(["python3", "/home/user/app/db_service.py"])
api = subprocess.Popen(["python3", "/home/user/app/api_service.py"])
monitor = subprocess.Popen(["python3", "/home/user/app/monitor_service.py"])

db.wait()
EOF

    chmod +x /home/user/app/*.py

    # Ensure SSH starts when the container is run or exec'd into
    echo "service ssh start > /dev/null 2>&1" >> /etc/bash.bashrc

    chmod -R 777 /home/user
