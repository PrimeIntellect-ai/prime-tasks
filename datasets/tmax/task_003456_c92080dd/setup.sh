#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip telnet
    pip3 install pytest pexpect

    mkdir -p /home/user/deployments

    cat << 'EOF' > /home/user/deployments/v1.conf
route 10.0.0.0/8 next-hop 192.168.1.1
firewall rule allow tcp port 80
EOF

    cat << 'EOF' > /home/user/deployments/v2.conf
route 10.0.0.0/8 next-hop 192.168.1.254
route 172.16.0.0/12 next-hop 192.168.1.254
firewall rule allow tcp port 80
firewall rule allow tcp port 443
EOF

    ln -sf /home/user/deployments/v1.conf /home/user/deployments/active

    cat << 'EOF' > /home/user/mock_router.py
import socket
import threading
import json
import os

def handle_client(conn):
    try:
        conn.sendall(b"Username: ")
        user = conn.recv(1024).decode('utf-8').strip()
        if user != 'admin':
            conn.sendall(b"Login failed\n")
            return

        conn.sendall(b"Password: ")
        password = conn.recv(1024).decode('utf-8').strip()
        if password != 'enable_secret':
            conn.sendall(b"Login failed\n")
            return

        conn.sendall(b"edge-router# ")

        mode = "normal"
        staged_config = []

        while True:
            data = conn.recv(1024)
            if not data:
                break
            cmd = data.decode('utf-8').strip()

            if mode == "normal":
                if cmd == "configure terminal":
                    mode = "config"
                    conn.sendall(b"edge-router(config)# ")
                elif cmd == "logout":
                    conn.sendall(b"Logged out\n")
                    break
                else:
                    conn.sendall(b"Unknown command\nedge-router# ")
            elif mode == "config":
                if cmd == "commit":
                    with open('/home/user/router_state.json', 'w') as f:
                        json.dump({"active_config": staged_config}, f)
                    conn.sendall(b"Commit successful.\r\nedge-router(config)# ")
                elif cmd == "exit":
                    mode = "normal"
                    conn.sendall(b"edge-router# ")
                elif cmd:
                    staged_config.append(cmd)
                    conn.sendall(b"edge-router(config)# ")
                else:
                    conn.sendall(b"edge-router(config)# ")
    except Exception as e:
        pass
    finally:
        conn.close()

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 5000))
    server.listen(5)
    while True:
        conn, addr = server.accept()
        t = threading.Thread(target=handle_client, args=(conn,))
        t.daemon = True
        t.start()

if __name__ == '__main__':
    start_server()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
