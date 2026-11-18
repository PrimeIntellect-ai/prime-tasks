#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go redis-server nginx
    pip3 install pytest

    mkdir -p /home/user/nginx
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8000;
        server_name localhost;

        # Add proxy pass here
    }
}
EOF

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create 50 clean files
    for i in $(seq 1 50); do
        cat << 'EOF' > /app/corpus/clean/clean_$i.json
{
    "services": [
        {"service_name": "web", "allocated_ram_mb": 1000.0, "cpu_shares": 50.0},
        {"service_name": "db", "allocated_ram_mb": 2000.0, "cpu_shares": 50.0}
    ]
}
EOF
    done

    # Create 50 evil files (violating RAM limit)
    for i in $(seq 1 50); do
        cat << 'EOF' > /app/corpus/evil/evil_$i.json
{
    "services": [
        {"service_name": "web", "allocated_ram_mb": 1000000.0, "cpu_shares": 50.0}
    ]
}
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/lib/nginx || true
    chmod -R 777 /var/log/nginx || true
    chmod -R 777 /run || true
