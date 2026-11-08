#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/services/logs /home/user/services/sockets /home/user/services/data_store
    touch /home/user/services/logs/processing.log

    dd if=/dev/urandom of=/home/user/services/data_store/file1.bin bs=1024 count=50
    dd if=/dev/urandom of=/home/user/services/data_store/file2.bin bs=1024 count=150

    cat << 'EOF' > /home/user/services/consumer.py
import socket, os, time

sock_path = "/home/user/services/sockets/app.sock"
if os.path.exists(sock_path):
    os.remove(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)

log_path = "/home/user/services/logs/processing.log"

while True:
    try:
        conn, addr = server.accept()
        data = conn.recv(1024)
        if data:
            with open(log_path, "a") as f:
                f.write(data.decode("utf-8") + "\n")
        conn.close()
    except Exception:
        pass
EOF

    cat << 'EOF' > /home/user/services/producer.py
import socket, time, random

sock_path = "/tmp/app.sock"

messages = [
    "INFO: Transaction processed",
    "INFO: Cache updated",
    "ERROR: Sync failed - target filesystem unresponsive"
]

while True:
    time.sleep(1)
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.connect(sock_path)
        msg = random.choice(messages)
        client.sendall(msg.encode("utf-8"))
        client.close()
    except Exception as e:
        pass
EOF

    chmod +x /home/user/services/producer.py /home/user/services/consumer.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
