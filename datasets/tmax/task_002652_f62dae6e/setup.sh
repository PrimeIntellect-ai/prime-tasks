#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx procps
    pip3 install pytest

    # Create logs directory and file
    mkdir -p /app/logs
    cat << 'EOF' > /app/logs/events.log
2023-10-25T09:00:00Z | INFO | latency=50ms | Bootup
2023-10-25T09:05:00Z | WARN | latency=-10ms | Time sync issue
2023-10-25T09:10:00Z | INFO | latency=120ms | User login
2023-10-25T09:15:00Z | ERROR | latency=NaNms | Segfault
2023-10-25T09:20:00Z | ERROR | latency=300ms | Database lock
2023-10-25T09:25:00Z | DEBUG | latency=15ms | Ping
2023-10-25T09:30:00Z | INFO | latency=210ms | Report generated
EOF

    # Configure Nginx for unprivileged execution
    cat << 'EOF' > /etc/nginx/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /tmp/client_temp;
    proxy_temp_path       /tmp/proxy_temp_path;
    fastcgi_temp_path     /tmp/fastcgi_temp;
    uwsgi_temp_path       /tmp/uwsgi_temp;
    scgi_temp_path        /tmp/scgi_temp;
    access_log /tmp/access.log;
    error_log /tmp/error.log;

    server {
        listen 8000;
        location /api/stats {
            proxy_pass http://127.0.0.1:8080/stats;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
