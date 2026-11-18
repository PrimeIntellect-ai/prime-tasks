#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick zip unzip fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 50,100 'MASTER_PASSWORD: R0tateMe2024!'" /app/diagram.png

    mkdir -p /home/user/infra_raw

    cat << 'EOF' > /home/user/infra_raw/ssh_config
Host *
    PasswordAuthentication yes
    IdentityFile ~/.ssh/id_rsa
EOF

    cat << 'EOF' > /home/user/infra_raw/nginx.conf
server {
    listen 80;
    server_name example.com;
    location / {
        root /var/www/html;
    }
}
EOF

    cat << 'EOF' > /home/user/infra_raw/access.log
192.168.1.100 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.0.5 - - [10/Oct/2023:13:56:10 -0700] "GET /../../../../etc/passwd HTTP/1.1" 403 512
192.168.1.101 - - [10/Oct/2023:13:57:00 -0700] "GET /about.html HTTP/1.1" 200 1024
192.168.1.102 - - [10/Oct/2023:13:58:22 -0700] "GET /images/%2e%2e%2f%2e%2e%2fetc/shadow HTTP/1.1" 403 512
192.168.1.103 - - [10/Oct/2023:13:59:01 -0700] "GET /contact HTTP/1.1" 200 850
10.0.0.6 - - [10/Oct/2023:14:00:15 -0700] "GET /api/v1/data?file=../config.json HTTP/1.1" 403 512
192.168.1.104 - - [10/Oct/2023:14:01:30 -0700] "GET /home HTTP/1.1" 200 1500
10.0.0.7 - - [10/Oct/2023:14:02:45 -0700] "GET /static/css/style.css HTTP/1.1" 200 3200
192.168.1.105 - - [10/Oct/2023:14:03:10 -0700] "GET /download?path=%2e%2e%2f%2e%2e%2f%2e%2e%2fetc/hosts HTTP/1.1" 403 512
10.0.0.8 - - [10/Oct/2023:14:04:05 -0700] "GET /uploads/../.env HTTP/1.1" 403 512
EOF

    cd /home/user/infra_raw
    zip -P R0tateMe2024! -r /home/user/infra.zip ./*
    cd /
    rm -rf /home/user/infra_raw

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
