#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd coreutils gawk sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/web_traffic.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024
192.168.1.11 - - [10/Oct/2023:13:56:01 +0000] "GET /style.css HTTP/1.1" 200 512
10.0.0.5 - - [10/Oct/2023:13:58:12 +0000] "GET /images/logo.png HTTP/1.1" 200 4096
172.16.45.99 - - [10/Oct/2023:14:02:11 +0000] "GET /search?q=%3Cscript%3Efetch('/exfil?data='+btoa(xor_encrypt(document.cookie)))%3C%2Fscript%3E HTTP/1.1" 200 512
192.168.1.10 - - [10/Oct/2023:14:03:05 +0000] "GET /contact HTTP/1.1" 200 1024
10.0.5.22 - - [10/Oct/2023:14:05:00 +0000] "GET /exfil?data=CRQ+CFQlC1RXYFMPWGBZD1UMUVQOJFRC HTTP/1.1" 404 128
192.168.1.15 - - [10/Oct/2023:14:06:22 +0000] "GET /about.html HTTP/1.1" 200 2048
EOF

    chmod -R 777 /home/user
