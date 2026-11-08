#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq openssl coreutils gawk grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/api_traffic.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /api/v1/data HTTP/1.1" 200 1024 "-" "Mozilla/5.0" "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIsImlhdCI6MTUxNjIzOTAyMn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
192.168.1.11 - - [10/Oct/2023:13:56:10 -0700] "POST /api/v1/admin HTTP/1.1" 201 512 "-" "curl/7.68.0" "Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbl91c2VyIiwiYWRtaW4iOnRydWV9."
192.168.1.12 - - [10/Oct/2023:13:57:02 -0700] "GET /api/v1/status HTTP/1.1" 200 256 "-" "PostmanRuntime/7.28.4" "Authorization: Bearer eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJzdWIiOiJzeXN0ZW1fYmFja2Rvb3IiLCJyb2xlIjoic3lzYWRtaW4ifQ."
192.168.1.13 - - [10/Oct/2023:13:58:15 -0700] "GET /api/v1/profile HTTP/1.1" 200 2048 "-" "Mozilla/5.0" "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSIsImlhdCI6MTUxNjIzOTAyMn0.xY1_..."
192.168.1.11 - - [10/Oct/2023:13:59:10 -0700] "POST /api/v1/admin HTTP/1.1" 201 512 "-" "curl/7.68.0" "Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbl91c2VyIiwiYWRtaW4iOnRydWV9."
EOF

    chmod -R 777 /home/user
