#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go git logrotate
pip3 install pytest

# Create required directories
mkdir -p /home/user/src /home/user/bin /home/user/logs

# Create user
useradd -m -s /bin/bash user || true

# Start background server automatically when the container is executed
cat << 'EOF' > /.singularity.d/env/99-start-server.sh
python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.bind(('127.0.0.1', 9090)); s.close()" 2>/dev/null && python3 -m http.server 9090 >/dev/null 2>&1 &
EOF
chmod +x /.singularity.d/env/99-start-server.sh

# Ensure permissions
chmod -R 777 /home/user
