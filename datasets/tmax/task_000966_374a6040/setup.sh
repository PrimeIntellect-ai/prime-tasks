#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_logs.txt
2023-10-01T10:00:01 [INFO] Startup complete
2023-10-01T10:00:02 [METRIC] service=auth-service response_time=120
2023-10-01T10:00:03 [DEBUG] Connecting to DB
2023-10-01T10:00:04 [METRIC] service=billing-service response_time=300
2023-10-01T10:00:05 [METRIC] service=auth-service response_time=130
2023-10-01T10:00:06 [ERROR] DB connection failed
2023-10-01T10:00:07 [METRIC] service=billing-service response_time=315
2023-10-01T10:00:08 [METRIC] service=inventory-service response_time=45
2023-10-01T10:00:09 [METRIC] service=auth-service response_time=125
2023-10-01T10:00:10 [METRIC] service=inventory-service response_time=50
EOF
    chmod 644 /home/user/raw_logs.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
