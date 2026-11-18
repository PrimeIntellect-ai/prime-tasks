#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev curl
    pip3 install pytest

    mkdir -p /home/user/app/redis
    mkdir -p /home/user/app/flask
    mkdir -p /home/user/app/nginx

    # Create legacy hash file
    echo -n "e150a1ec81e8e93e1eae2c3a77e66ec8dbd6ca0cbfa943be8a3a00ed4e5e40e8" > /home/user/app/legacy_hash.txt

    # Create initial Redis conf
    cat << 'EOF' > /home/user/app/redis/redis.conf
requirepass 839210
EOF

    # Create initial Flask .env
    cat << 'EOF' > /home/user/app/flask/.env
REDIS_PASSWORD=839210
EOF

    # Create initial Nginx conf
    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            proxy_pass http://localhost:5000/;
        }
        location /auth/ {
            proxy_pass http://localhost:8000/;
        }
        location /auth-debug/ {
            proxy_pass http://localhost:8081/;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
