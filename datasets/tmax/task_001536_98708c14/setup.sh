#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_logs.csv
timestamp,ip_address,method,endpoint,user_agent
2023-10-01T10:00:00Z,192.168.1.5,get,/api/v1/data,Mozilla/5.0
2023-10-01T10:05:00Z,192.168.1.5,GET,/api/v1/data,Mozilla/5.0
2023-10-01T10:10:00Z,10.0.0.15,post,/api/v1/login,curl/7.68.0
2023-10-01T09:55:00Z,192.168.1.100,GeT,/api/v1/data,Mozilla/5.0
2023-10-01T10:15:00Z,172.16.254.1,OPTIONS,/api/v1/data,PostmanRuntime/7.28.4
EOF

    chmod -R 777 /home/user
