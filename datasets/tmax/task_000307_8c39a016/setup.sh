#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/historical.log
[2023-10-01 12:00:00] INFO 192.168.1.5 GET /index.html 200
[2023-10-01 12:01:00] ERROR 10.0.0.5 GET /admin 404
[2023-10-01 12:02:00] ERROR 10.0.0.5 GET /config 404
[2023-10-01 12:03:00] ERROR 192.168.1.50 GET /wp-admin 404
[2023-10-01 12:04:00] ERROR 10.0.0.5 GET /login 404
[2023-10-01 12:05:00] INFO 172.16.0.2 GET / 200
[2023-10-01 12:06:00] ERROR 172.16.0.2 GET /hidden 404
[2023-10-01 12:07:00] ERROR 192.168.1.50 GET /wp-login 404
[2023-10-01 12:08:00] ERROR 192.168.1.50 GET /dbadmin 404
[2023-10-01 12:09:00] ERROR 192.168.1.50 GET /backup 404
[2023-10-01 12:10:00] ERROR 10.10.10.10 GET /shell 404
[2023-10-01 12:11:00] ERROR 10.10.10.10 GET /cmd 404
EOF

    chmod -R 777 /home/user
