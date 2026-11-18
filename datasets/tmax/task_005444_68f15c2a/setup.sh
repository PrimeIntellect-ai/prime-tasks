#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user

    # Fix imagemagick policy to allow drawing text
    sed -i 's/<policy domain="path" rights="none" pattern="@\*"\/>/<!-- <policy domain="path" rights="none" pattern="@*"\/> -->/g' /etc/ImageMagick-6/policy.xml || true

    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'ARCHITECTURE: NGINX -> C++ BACKEND (PORT 8453)'" /app/architecture.png

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    echo -e "GET /index.html HTTP/1.1\nHost: localhost" > /app/corpus/clean/clean_1.txt
    echo -e "POST /login HTTP/1.1\nHost: localhost\n\nuser=admin" > /app/corpus/clean/clean_2.txt
    echo -e "GET /api/data?id=123 HTTP/1.1" > /app/corpus/clean/clean_3.txt

    echo -e "GET /api/data?id=\$(rm -rf /) HTTP/1.1" > /app/corpus/evil/evil_1.txt
    echo -e "POST /login HTTP/1.1\n\nuser=admin' UNION SELECT * FROM users--" > /app/corpus/evil/evil_2.txt
    echo -e "GET /index.html?q=\`whoami\` HTTP/1.1" > /app/corpus/evil/evil_3.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
