#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat g++
    pip3 install pytest

    mkdir -p /home/user/app /home/user/deploy

    cat << 'EOF' > /home/user/app/server.conf
# Backend Server Configuration
MAX_THREADS=4
BIND_PATH=/home/user/app/app_v2.sock
TIMEOUT=30
EOF

    cat << 'EOF' > /home/user/deploy/proxy.conf
server {
    listen 8080;
    server_name localhost;

    location / {
        proxy_pass http://unix:/home/user/app/app_v1.sock;
        proxy_set_header Host $host;
    }
}
EOF

    # Create the socket file so it exists for initial state checks
    python3 -c "import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind('/home/user/app/app_v2.sock')"
    chmod 777 /home/user/app/app_v2.sock

    useradd -m -s /bin/bash user || true

    # Ensure socat is running when the user starts a session
    cat << 'EOF' >> /home/user/.bashrc
if ! pgrep -x "socat" > /dev/null; then
    rm -f /home/user/app/app_v2.sock
    socat UNIX-LISTEN:/home/user/app/app_v2.sock,fork EXEC:"echo OK" &
    sleep 0.5
    chmod 777 /home/user/app/app_v2.sock
fi
EOF

    chmod -R 777 /home/user
