#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps socat expect iproute2 netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create the worker daemon
    cat << 'EOF' > /home/user/worker_daemon.sh
#!/bin/bash
while true; do
  sleep 1
done
EOF
    chmod +x /home/user/worker_daemon.sh

    # 2. Create the mock legacy daemon
    cat << 'EOF' > /home/user/legacy_daemon.py
import socket
import threading

def handle_client(conn):
    try:
        conn.sendall(b"Username: ")
        user = conn.recv(1024).decode().strip()
        if user != "admin":
            conn.sendall(b"Access Denied\n")
            conn.close()
            return

        conn.sendall(b"Password: ")
        pw = conn.recv(1024).decode().strip()
        if pw != "cap_planner":
            conn.sendall(b"Access Denied\n")
            conn.close()
            return

        while True:
            conn.sendall(b"CMD> ")
            cmd = conn.recv(1024).decode().strip()
            if cmd == "STATS":
                conn.sendall(b"[System Status]\nActive Connections: 404\nCurrent Bandwidth: 120 Mbps\n")
            elif cmd == "QUIT":
                conn.sendall(b"Goodbye\n")
                break
            else:
                conn.sendall(b"Unknown command\n")
    except Exception as e:
        pass
    finally:
        conn.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', 9999))
server.listen(5)

while True:
    client, _ = server.accept()
    threading.Thread(target=handle_client, args=(client,)).start()
EOF

    # Create a script to start daemons on container execution
    cat << 'EOF' > /.singularity.d/env/99-daemons.sh
if ! pgrep -f worker_daemon.sh > /dev/null; then
    nohup /home/user/worker_daemon.sh >/dev/null 2>&1 &
fi
if ! pgrep -f legacy_daemon.py > /dev/null; then
    nohup python3 /home/user/legacy_daemon.py >/dev/null 2>&1 &
fi
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
