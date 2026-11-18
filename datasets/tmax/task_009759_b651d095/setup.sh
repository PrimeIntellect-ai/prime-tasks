#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron openssl gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs /home/user/certs /home/user/backup

    cat << 'EOF' > /home/user/app_logs/access.log
192.168.1.10 - - [01/Jan/2024:12:00:00 +0000] "GET /img.jpg HTTP/1.1" 200 5000
10.0.0.5 - - [01/Jan/2024:12:01:00 +0000] "GET /vid.mp4 HTTP/1.1" 200 150000
192.168.1.10 - - [01/Jan/2024:12:02:00 +0000] "GET /index.html HTTP/1.1" 200 1000
172.16.0.2 - - [01/Jan/2024:12:03:00 +0000] "GET /doc.pdf HTTP/1.1" 200 45000
10.0.0.5 - - [01/Jan/2024:12:04:00 +0000] "GET /vid2.mp4 HTTP/1.1" 200 200000
192.168.1.20 - - [01/Jan/2024:12:05:00 +0000] "GET /style.css HTTP/1.1" 200 8000
192.168.1.10 - - [01/Jan/2024:12:06:00 +0000] "GET /favicon.ico HTTP/1.1" 200 500
EOF

    chmod -R 777 /home/user
