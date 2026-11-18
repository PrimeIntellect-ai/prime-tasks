#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git netcat-openbsd socat curl procps
    pip3 install pytest

    mkdir -p /home/user/repo.git /home/user/deploy /home/user/backups /home/user/workspace
    git init --bare /home/user/repo.git

    echo "Hello World" > /home/user/deploy/index.html

    cat << 'EOF' > /home/user/proxy.sh
#!/bin/bash
if ! nc -z 127.0.0.1 8081; then
    echo "Backend not ready. Proxy crashing."
    exit 1
fi
echo "Proxy started."
# Simple port forward using socat or a proxy simulation
socat TCP-LISTEN:8080,fork,bind=127.0.0.1 TCP:127.0.0.1:8081
EOF
    chmod +x /home/user/proxy.sh

    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
pkill -f "python3 -m http.server 8081" || true
pkill -f "/home/user/proxy.sh" || true
pkill -f "socat TCP-LISTEN:8080" || true

# Bug: starts proxy before backend, no backup
/home/user/proxy.sh &
python3 -m http.server 8081 --bind 127.0.0.1 --directory /home/user/deploy &
EOF
    chmod +x /home/user/deploy.sh

    cat << 'EOF' > /home/user/.gitconfig
[user]
	name = User
	email = user@example.com
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
