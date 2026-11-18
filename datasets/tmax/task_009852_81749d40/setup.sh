#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/proxy_logs.txt
10.0.0.5 - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 "{\"User-Agent\": \"Mozilla\"}" "{\"session_role\": \"guest\"}"
192.168.1.50 - [10/Oct/2023:14:01:12 +0000] "GET /admin/secrets HTTP/1.1" 403 "{\"User-Agent\": \"curl/7.68.0\"}" "{\"session_role\": \"user\"}"
192.168.1.50 - [10/Oct/2023:14:02:05 +0000] "GET /admin/secrets HTTP/1.1" 403 "{\"User-Agent\": \"curl/7.68.0\", \"X-Internal-IP\": \"127.0.0.1\"}" "{\"session_role\": \"user\"}"
192.168.1.50 - [10/Oct/2023:14:05:10 +0000] "GET /admin/secrets HTTP/1.1" 200 "{\"User-Agent\": \"curl/7.68.0\", \"X-Internal-IP\": \"127.0.0.1\"}" "{\"session_role\": \"admin\"}"
172.16.0.10 - [10/Oct/2023:14:10:00 +0000] "GET /admin/dashboard HTTP/1.1" 200 "{\"User-Agent\": \"Chrome\", \"X-Internal-IP\": \"127.0.0.1\"}" "{\"session_role\": \"admin\"}"
EOF

    chmod -R 777 /home/user
