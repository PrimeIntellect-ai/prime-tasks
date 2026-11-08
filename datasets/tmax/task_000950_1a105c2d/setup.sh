#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/web_app/public/images
    mkdir -p /home/user/web_app/public/docs
    mkdir -p /home/user/quarantine

    cat << 'EOF' > /home/user/logs/access.log
192.168.1.15 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "GET /images/logo.png HTTP/1.1" 200 512
203.0.113.42 - - [10/Oct/2023:14:01:12 -0700] "GET /docs/backup.pem HTTP/1.1" 404 123
192.168.1.15 - - [10/Oct/2023:14:02:11 -0700] "GET /about.html HTTP/1.1" 200 1024
198.51.100.7 - - [10/Oct/2023:14:05:00 -0700] "GET /id_rsa HTTP/1.1" 200 1679
10.0.0.5 - - [10/Oct/2023:14:10:22 -0700] "GET /admin.key HTTP/1.1" 403 234
198.51.100.7 - - [10/Oct/2023:14:15:33 -0700] "GET /.ssh/id_rsa HTTP/1.1" 200 1679
EOF

    echo "Just a normal text file" > /home/user/web_app/public/docs/readme.txt
    echo "Fake image data" > /home/user/web_app/public/images/fake.jpg

    cat << 'EOF' > /home/user/web_app/public/docs/backup.txt
Some preamble
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA...
-----END RSA PRIVATE KEY-----
EOF

    cat << 'EOF' > /home/user/web_app/public/dev_key.pem
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAA...
-----END OPENSSH PRIVATE KEY-----
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
