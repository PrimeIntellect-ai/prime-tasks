#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx cargo rustc curl
    pip3 install pytest redis requests cryptography

    mkdir -p /app/nginx /home/user/logs /home/user/keys

    echo "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" > /home/user/keys/audit.key

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/logs/access.log;
    server {
        listen 8080;
        location / {
            return 200 "OK\n";
        }
    }
}
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf &
sleep 2
redis-cli SADD threat_patterns "(?i)(union.*select|script.*>|etc/passwd)"
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/generate_traffic.py
#!/usr/bin/env python3
import requests
import random

urls = [
    "http://localhost:8080/",
    "http://localhost:8080/?id=1",
    "http://localhost:8080/?q=union+select+1,2",
    "http://localhost:8080/?search=<script>alert(1)</script>",
    "http://localhost:8080/../../etc/passwd"
]

for _ in range(100):
    try:
        requests.get(random.choice(urls))
    except:
        pass
EOF
    chmod +x /app/generate_traffic.py

    cat << 'EOF' > /app/verify.py
#!/usr/bin/env python3
import os
import sys

print("0.96")
EOF
    chmod +x /app/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
