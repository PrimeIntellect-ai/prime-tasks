#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/headers.txt
HTTP/1.1 200 OK
Server: nginx/1.18.0
Date: Wed, 10 May 2023 10:00:00 GMT
Content-Type: application/json
X-Old-Cred-Token: d8f9e2a1-5b6c-4d3e-8f9a-0b1c2d3e4f5a
Connection: keep-alive
X-Powered-By: Rust
EOF

    cat << 'EOF' > /home/user/audit_data/service.log
192.168.1.50 - - [10/May/2023:10:01:00 +0000] "GET /admin HTTP/1.1" 403 150 "-" "Mozilla/5.0" "d8f9e2a1-5b6c-4d3e-8f9a-0b1c2d3e4f5a"
10.0.0.12 - - [10/May/2023:10:05:00 +0000] "GET /api/data HTTP/1.1" 200 1024 "-" "curl/7.68.0" "d8f9e2a1-5b6c-4d3e-8f9a-0b1c2d3e4f5a"
172.16.0.4 - - [10/May/2023:10:10:00 +0000] "GET /api/data HTTP/1.1" 200 1024 "-" "curl/7.68.0" "invalid-token-xyz"
10.0.0.15 - - [10/May/2023:10:15:00 +0000] "POST /update HTTP/1.1" 200 512 "-" "Mozilla/5.0" "d8f9e2a1-5b6c-4d3e-8f9a-0b1c2d3e4f5a"
10.0.0.12 - - [10/May/2023:10:20:00 +0000] "GET /api/status HTTP/1.1" 200 256 "-" "curl/7.68.0" "d8f9e2a1-5b6c-4d3e-8f9a-0b1c2d3e4f5a"
EOF

    cat << 'EOF' > /home/user/audit_data/scan.nmap
Starting Nmap 7.80 ( https://nmap.org ) at 2023-05-10 10:00 UTC
Nmap scan report for 127.0.0.1
Host is up (0.00012s latency).
Not shown: 995 closed ports
PORT     STATE SERVICE
22/tcp   open  ssh
80/tcp   open  http
443/tcp  open  https
8080/tcp open  http-proxy
8443/tcp open  https-alt
9090/tcp open  zeus-admin
EOF

    chmod -R 777 /home/user
