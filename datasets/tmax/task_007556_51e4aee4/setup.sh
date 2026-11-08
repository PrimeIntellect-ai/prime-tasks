#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    mkdir -p /home/user/logs

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/ca.key -out /home/user/certs/ca.crt -days 365 -nodes -subj "/CN=Internal_Root_CA"
    openssl req -newkey rsa:2048 -keyout /home/user/certs/server.key -out /home/user/certs/server.csr -nodes -subj "/CN=secure.internal.corp"
    openssl x509 -req -in /home/user/certs/server.csr -CA /home/user/certs/ca.crt -CAkey /home/user/certs/ca.key -CAcreateserial -out /home/user/certs/server.crt -days 365

    cat << 'EOF' > /home/user/logs/waf.log
2023-10-01 10:00:01 WARN [SQLI] 192.168.1.50 - Payload: ' OR 1=1
2023-10-01 10:05:00 WARN [XSS] 192.168.1.50 - Payload: <script>alert(1)</script>
2023-10-01 10:10:00 WARN [SQLI] 10.0.0.6 - Payload: admin' --
2023-10-01 10:15:00 WARN [XSS] 172.16.0.5 - Payload: onload=alert(1)
2023-10-01 10:20:00 WARN [SQLI] 192.168.1.100 - Payload: UNION SELECT
2023-10-01 10:25:00 WARN [XSS] 192.168.1.100 - Payload: javascript:alert(1)
2023-10-01 10:30:00 WARN [SQLI] 192.168.1.100 - Payload: drop table users
EOF

    chmod -R 777 /home/user
