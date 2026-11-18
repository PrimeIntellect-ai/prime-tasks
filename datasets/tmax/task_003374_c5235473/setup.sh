#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl redis-server nginx cargo
    pip3 install pytest

    mkdir -p /app/nginx /app/backend/src /app/redis /app/corpus/evil /app/corpus/clean /app/logs

    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /app/backend/.env
REDIS_URL=redis://redis:6379
EOF

    cat << 'EOF' > /app/corpus/evil/urls.txt
http://169.254.169.254/latest/meta-data/
http://2130706433/
https://expected-domain.com@evil.com/
EOF

    cat << 'EOF' > /app/corpus/clean/urls.txt
https://myapp.com/dashboard
/settings/profile
EOF

    cat << 'EOF' > /app/logs/suspicious.log
[INFO] Request to /api/login?redirect=http://169.254.169.254/latest/meta-data/
[INFO] Request to /api/login?redirect=http://2130706433/
EOF

    cat << 'EOF' > /app/backend/Cargo.toml
[package]
name = "backend"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/backend/src/main.rs
fn main() {
    println!("Mock backend running on port 8081");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
