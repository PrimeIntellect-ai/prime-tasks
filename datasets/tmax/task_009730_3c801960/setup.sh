#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
203.0.113.42 - - [05/Nov/2023:08:14:02 +0000] "GET /index.html HTTP/1.1" 200 1024
198.51.100.17 - - [05/Nov/2023:09:21:55 +0000] "GET /admin/config.php HTTP/1.1" 404 512
192.0.2.8 - - [05/Nov/2023:09:25:12 +0000] "POST /login HTTP/1.1" 404 512
203.0.113.99 - - [06/Nov/2023:14:10:00 +0000] "GET /images/logo.png HTTP/1.1" 200 4096
198.51.100.201 - - [06/Nov/2023:14:15:33 +0000] "GET /api/v1/users HTTP/1.1" 404 128
10.0.0.55 - - [07/Dec/2023:11:00:00 +0000] "GET /nonexistent HTTP/1.1" 404 256
172.16.0.4 - - [08/Dec/2023:12:34:56 +0000] "GET /old-page.html HTTP/1.1" 301 0
192.168.1.100 - - [09/Dec/2023:23:59:59 +0000] "GET /hidden/admin.env HTTP/1.1" 404 1024
EOF

    chmod -R 777 /home/user
