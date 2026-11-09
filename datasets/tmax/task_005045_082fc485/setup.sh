#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y expect netcat-openbsd telnet git iproute2

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_iot_device.py
import socket
import sys
import threading

def handle_client(conn):
    try:
        conn.sendall(b"Device login:")
        data = conn.recv(1024).decode('utf-8').strip()
        if data == "edgeAdmin":
            conn.sendall(b"Command>")
            cmd = conn.recv(1024).decode('utf-8').strip()
            if cmd.startswith("SYNC "):
                path = cmd.split(" ", 1)[1]
                with open("/home/user/device_sync_log.txt", "w") as f:
                    f.write(f"SYNC_SUCCESS: {path}\n")
                conn.sendall(b"OK\n")
            else:
                conn.sendall(b"ERROR\n")
        else:
            conn.sendall(b"AUTH_FAILED\n")
    except Exception as e:
        pass
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8888))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        t = threading.Thread(target=handle_client, args=(conn,))
        t.start()

if __name__ == "__main__":
    main()
EOF

    # Start the IoT dummy server in the background
    python3 /home/user/setup_iot_device.py &
    echo $! > /home/user/iot_server.pid

    # To ensure it runs when the container starts
    echo "python3 /home/user/setup_iot_device.py & echo \$! > /home/user/iot_server.pid" >> /home/user/.bashrc

    chmod -R 777 /home/user
