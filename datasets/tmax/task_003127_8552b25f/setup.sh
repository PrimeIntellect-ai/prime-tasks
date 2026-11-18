#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl faketime
    pip3 install pytest

    mkdir -p /home/user/certs
    mkdir -p /home/user/logs

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/valid.key -out /home/user/certs/valid.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Org/CN=secure-api.internal.com" 2>/dev/null
    faketime '2020-01-01 00:00:00' openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/expired.key -out /home/user/certs/expired.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Org/CN=legacy-api.internal.com" 2>/dev/null

    rm -f /home/user/certs/*.key

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /api/v1/status HTTP/1.1" 200 512 "-" "Mozilla/5.0 Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSIsInJvbGUiOiJ1c2VyIn0.sig"
10.0.0.5 - - [10/Oct/2023:14:12:01 +0000] "POST /api/v1/admin HTTP/1.1" 201 1024 "-" "Curl/7.68.0 Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhdHRhY2tlcl9ib2IiLCJyb2xlIjoiYWRtaW4ifQ."
172.16.0.4 - - [10/Oct/2023:14:15:22 +0000] "DELETE /api/v1/users/1 HTTP/1.1" 403 128 "-" "Python-requests/2.25.1 Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJyb2d1ZV9jaGFybGllIiwiZXhwIjoxOTk5OTk5OTk5fQ."
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/certs /home/user/access.log
    chmod -R 777 /home/user
