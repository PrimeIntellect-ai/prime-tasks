#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx curl cargo
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# NGINX setup
mkdir -p /home/user/nginx/client_body \
         /home/user/nginx/fastcgi_temp \
         /home/user/nginx/proxy_temp \
         /home/user/nginx/scgi_temp \
         /home/user/nginx/uwsgi_temp

cat << 'EOF' > /home/user/nginx/nginx.conf
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/error.log;
events {}
http {
    client_body_temp_path /home/user/nginx/client_body;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    access_log /home/user/nginx/access.log;

    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

# Start nginx on bash startup
echo "nginx -c /home/user/nginx/nginx.conf 2>/dev/null || true" >> /etc/bash.bashrc
echo "nginx -c /home/user/nginx/nginx.conf 2>/dev/null || true" >> /home/user/.bashrc

# Rust package setup
mkdir -p /app/upstream-service-1.2.0/src
cat << 'EOF' > /app/upstream-service-1.2.0/Cargo.toml
[package]
name = "upstream-service"
version = "1.2.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
axum = "0.7"
EOF

cat << 'EOF' > /app/upstream-service-1.2.0/src/main.rs
use axum::{routing::get, Router};

#[tokio::main]
async fn main() {
    let app = Router::new().route("/", get(|| async { "Hello, World!" }));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:9999").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
EOF

# Deploy directories
mkdir -p /home/user/deploy/releases/v1
ln -s /home/user/deploy/releases/v1 /home/user/deploy/current

# Load test script
cat << 'EOF' > /home/user/test_load.py
#!/usr/bin/env python3
import urllib.request
import json
import time

success_count = 0
total = 10

for _ in range(total):
    try:
        req = urllib.request.Request("http://127.0.0.1:8080")
        with urllib.request.urlopen(req, timeout=2) as response:
            if response.getcode() == 200:
                success_count += 1
    except Exception:
        pass
    time.sleep(0.1)

success_rate = success_count / total
with open("/home/user/metrics.txt", "w") as f:
    json.dump({"success_rate": success_rate}, f)
print(json.dumps({"success_rate": success_rate}))
EOF
chmod +x /home/user/test_load.py

chmod -R 777 /home/user
chmod -R 777 /app
