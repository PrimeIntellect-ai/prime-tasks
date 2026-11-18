#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/gateway.log
192.168.1.10 [10/Oct/2023:13:55:36 -0000] 8080 "GET /login?redirect=/dashboard HTTP/1.1" 302 123 "tok_123abc"
10.0.0.5 [10/Oct/2023:14:02:11 -0000] 8081 "GET /login?redirect=https://attacker.com/ HTTP/1.1" 400 54 "tok_456def"
192.168.1.11 [10/Oct/2023:14:05:00 -0000] 8080 "GET /login?redirect=/settings HTTP/1.1" 302 123 "tok_111qwe"
172.16.0.4 [10/Oct/2023:14:15:22 -0000] 8082 "GET /login?redirect=http://evil-site.net/steal HTTP/1.1" 302 145 "tok_789ghi"
10.0.0.8 [10/Oct/2023:14:20:01 -0000] 8083 "POST /login HTTP/1.1" 200 400 "tok_000zzz"
EOF

    chmod -R 777 /home/user
