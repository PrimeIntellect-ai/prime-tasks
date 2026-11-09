#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.log
[2023-10-01 10:00:00] IP=10.0.0.5 GET /rotate?PASSWORD=OldSecret123 HTTP/1.1
[2023-10-01 10:05:00] IP=192.168.1.10 GET /status HTTP/1.1
[2023-10-01 10:10:00] IP=172.16.0.4 POST /rotate?API_KEY=Key999 HTTP/1.1
[2023-10-01 10:15:00] IP=10.0.0.5 GET /rotate?PASSWORD=NewSecret456 HTTP/1.1
[2023-10-01 10:20:00] IP=10.1.1.1 POST /login USER=admin HTTP/1.1
EOF

    chmod -R 777 /home/user
