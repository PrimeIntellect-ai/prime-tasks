#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_service

    cat << 'EOF' > /home/user/legacy_service/app.py
import socket
import sys

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8888))
    s.listen(1)

    connections = 0
    while True:
        try:
            conn, addr = s.accept()
            connections += 1
            conn.close()
            # Simulate a crash after 4 connections
            if connections >= 4:
                sys.exit(1)
        except Exception:
            sys.exit(1)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/legacy_service/start.sh
#!/bin/bash
# Kill existing just in case
pkill -f "python3 /home/user/legacy_service/app.py" 2>/dev/null
# Start new instance
nohup python3 /home/user/legacy_service/app.py >/dev/null 2>&1 &
EOF
    chmod +x /home/user/legacy_service/start.sh

    # Ensure the service starts when a shell is opened
    echo "/home/user/legacy_service/start.sh" >> /home/user/.bashrc
    echo "/home/user/legacy_service/start.sh" >> /root/.bashrc

    chmod -R 777 /home/user
