#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifests/01_app.json
{
  "route": "/app",
  "target_port": 8080,
  "allowed_ips": ["10.0.0.0/8"]
}
EOF

    cat << 'EOF' > /home/user/manifests/99_app_override.json
{
  "route": "/app",
  "target_port": 8081,
  "allowed_ips": ["10.0.0.0/8", "192.168.1.1"]
}
EOF

    cat << 'EOF' > /home/user/manifests/50_api.json
{
  "route": "/api/v1",
  "target_port": 9090,
  "allowed_ips": ["0.0.0.0/0"]
}
EOF

    cat << 'EOF' > /home/user/manifests/broken.json
{
  "route": "/broken",
  "target_port": 80,
  "allowed_ips": ["1.2.3.4"]
EOF

    cat << 'EOF' > /home/user/manifests/incomplete.json
{
  "route": "/incomplete",
  "target_port": 8080
}
EOF

    chmod -R 777 /home/user
