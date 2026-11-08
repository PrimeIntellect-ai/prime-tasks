#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/discovery.log
[2023-10-24 10:00:01] [INFO] Starting discovery service
[2023-10-24 10:00:02] [DEBUG] Initializing random socket allocation
[2023-10-24 10:00:03] [INFO] Daemon bound to socket BIND_ADDR=/tmp/runtime-user/app_sock_7b98f2.sock
[2023-10-24 10:00:04] [INFO] Ready for connections
EOF

    cat << 'EOF' > /home/user/app/generate_config.sh
#!/bin/bash
SOCKET_PATH="/tmp/app.sock"
echo "upstream backend { server unix:${SOCKET_PATH}; }" > /home/user/app/nginx-upstream.conf
EOF
    chmod +x /home/user/app/generate_config.sh

    cat << 'EOF' > /home/user/app/daemon.log
ERROR: Connection refused to /tmp/app.sock
ERROR: Upstream unavailable
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
