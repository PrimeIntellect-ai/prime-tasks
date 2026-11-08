#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/web.csv
timestamp,status_code,ip_address,user_agent
2023-10-01T10:00:00,200,192.168.1.100,Mozilla
2023-10-01T10:05:00,403,10.5.5.1,curl
2023-10-01T10:10:00,403,172.16.0.5,Postman
2023-10-01T10:15:00,500,10.5.5.1,curl
EOF

    cat << 'EOF' > /home/user/logs/api.json
[
  {"time": "2023-10-01T11:00", "event": "Auth successful 200", "client_ip": "192.168.1.101"},
  {"time": "2023-10-01T11:05", "event": "Failed Auth 403 Forbidden", "client_ip": "10.5.5.1"},
  {"time": "2023-10-01T11:10", "event": "Rate limit 403", "client_ip": "8.8.8.8"}
]
EOF

    cat << 'EOF' > /home/user/logs/legacy.log
[INFO] Connection from 192.168.1.50 accepted at 12:00
[ERROR] 12:05 - Connection dropped for 10.5.5.1 due to 403 Forbidden
[WARN] 12:10 - Invalid payload from 10.0.0.9 (Error 500)
[ERROR] 12:15 - Blocked 172.16.0.5 with code 403
[ERROR] 12:20 - Blocked 9.9.9.9 with code 403
EOF

    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
