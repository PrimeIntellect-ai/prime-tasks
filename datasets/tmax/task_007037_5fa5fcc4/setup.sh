#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip haproxy curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/capacity_planner

    cat << 'EOF' > /home/user/capacity_planner/start_backends.sh
#!/bin/bash
# Start backend nodes
cd /home/user/capacity_planner
nohup python3 -m http.server 8081 --bind 127.0.0.1 > node1.log 2>&1 &
nohup python3 -m http.server 80 --bind 127.0.0.1 > node2.log 2>&1 &
nohup python3 -m http.server 8083 --bind 127.0.0.2 > node3.log 2>&1 &
EOF
    chmod +x /home/user/capacity_planner/start_backends.sh

    cat << 'EOF' > /home/user/capacity_planner/haproxy.cfg
global
    maxconn 100

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http-in
    bind 127.0.0.1:80
    default_backend servers

backend servers
    server server1 127.0.0.1:9081
    server server2 127.0.0.1:9082
    server server3 127.0.0.1:9083
EOF

    chmod -R 777 /home/user
