#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +20+40 "Server Configuration Spec\nBackend Socket: unix:/home/user/run/backend.sock\nRate Limit: 35 req/sec" /app/config_spec.png

    # Create the Nginx config
    cat << 'EOF' > /home/user/nginx.conf
http {
    upstream backend {
        server unix:/tmp/wrong.sock;
    }
    server {
        listen 80;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    # Generate access.log
    python3 -c '
with open("/app/access.log", "w") as f:
    for _ in range(36):
        f.write("192.168.1.100 - - [10/Oct/2023:13:55:36 +0000] \"GET / HTTP/1.1\" 200 123\n")
    for _ in range(40):
        f.write("10.0.0.55 - - [10/Oct/2023:13:56:01 +0000] \"GET / HTTP/1.1\" 200 123\n")
    for _ in range(10):
        f.write("172.16.0.10 - - [10/Oct/2023:13:57:00 +0000] \"GET / HTTP/1.1\" 200 123\n")
    for _ in range(20):
        f.write("192.168.1.200 - - [10/Oct/2023:13:58:00 +0000] \"GET / HTTP/1.1\" 200 123\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
