#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8000;
        location / {
            proxy_pass http://127.0.0.1:8080; # DELIBERATE ERROR: Agent must change 8080 to 9000
        }
    }
}
EOF

    echo "secret_payload_content" > /app/test_file.txt
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
