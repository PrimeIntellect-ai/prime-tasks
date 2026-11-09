#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user/finops-scale/sockets
    mkdir -p /home/user/finops-scale/shared_data
    touch /home/user/data-disk.img
    echo "STATUS:IDLE" > /home/user/finops-scale/metrics.log

    cat << 'EOF' > /home/user/finops-scale/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/tmp/backend.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/finops-scale/mock-worker.py
import time
while True:
    time.sleep(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
