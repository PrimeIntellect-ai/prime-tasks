#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/microservices/lb
    mkdir -p /tmp/

    cat << 'EOF' > /home/user/microservices/generate_base.py
import os
import sys

def main():
    target_path = os.environ.get('LB_CONF_PATH', '/tmp/base.cfg')
    config_content = """global
    maxconn 4096
    log 127.0.0.1 local0
defaults
    mode http
    timeout connect 5s
    timeout client 50s
    timeout server 50s
"""
    try:
        with open(target_path, 'w') as f:
            f.write(config_content)
        print(f"Base config written to {target_path}")
    except Exception as e:
        print(f"Failed to write config: {e}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/microservices/generate_base.py

    cat << 'EOF' > /home/user/microservices/registry.txt
auth_svc UP 8081
cache_svc DOWN 8082
user_svc UP 8083
payment_svc DOWN 8084
inventory_svc UP 8085
EOF

    cat << 'EOF' > /home/user/microservices/mock_socket.py
import socket
import os

sock_file = "/home/user/microservices/legacy.sock"
if os.path.exists(sock_file):
    try:
        os.remove(sock_file)
    except:
        pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_file)
server.listen(1)

while True:
    try:
        conn, addr = server.accept()
        conn.sendall(b"Enter PIN: ")
        data = conn.recv(1024).decode('utf-8').strip()
        if data == "8472":
            conn.sendall(b"Backend port is 9050\n")
        else:
            conn.sendall(b"Invalid PIN\n")
        conn.close()
    except:
        pass
EOF

    # Start the mock socket service automatically when the container runs
    cat << 'EOF' > /.singularity.d/env/99-mock.sh
#!/bin/sh
if ! ps -ef | grep -v grep | grep -q mock_socket.py; then
    python3 /home/user/microservices/mock_socket.py >/dev/null 2>&1 &
    sleep 0.5
fi
EOF
    chmod +x /.singularity.d/env/99-mock.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
