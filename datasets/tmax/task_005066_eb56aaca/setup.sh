#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    mkdir -p /home/user/incident

    cat << 'EOF' > /home/user/incident/backend_server.py
import socket

def start_server():
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(('127.0.0.1', 9000))
    server_socket.listen(5)

    while True:
        client_socket, addr = server_socket.accept()
        try:
            data = client_socket.recv(1024).decode('utf-8')
            if data.strip() == "REVOKE_TOKEN 8f9b2a1c4e":
                client_socket.sendall(b"SUCCESS: FLAG_PROC_LEAK_REMEDIATED_9921\n")
            else:
                client_socket.sendall(b"ERROR: INVALID TOKEN\n")
        except Exception:
            pass
        finally:
            client_socket.close()

if __name__ == "__main__":
    start_server()
EOF

    cat << 'EOF' > /home/user/incident/rogue_actor.py
import time
import sys

def main():
    while True:
        time.sleep(10)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/incident/start_scenario.sh
#!/bin/bash
cd /home/user/incident
python3 backend_server.py &
python3 rogue_actor.py --stolen-auth-token=8f9b2a1c4e &
EOF
    chmod +x /home/user/incident/start_scenario.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
