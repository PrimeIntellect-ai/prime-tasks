#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go jq
    pip3 install pytest

    mkdir -p /home/user/logs /home/user/config

    cat << 'EOF' > /home/user/logs/services.log
[2023-10-25 10:15:00 UTC] db-service OK All checks passed
[2023-10-25 14:30:00 PDT] auth-service ERROR Connection Refused to backend
[2023-10-25 17:45:00 EST] cache-service WARN High memory usage
[2023-10-26 09:00:00 JST] payment-service ERROR Connection Refused from gateway
[2023-10-26 01:20:00 UTC] unknown-service ERROR Connection Refused on port 8080
[2023-10-26 08:30:00 PDT] auth-service ERROR Invalid Credentials
EOF

    cat << 'EOF' > /home/user/config/service_groups.conf
db-service:db-admins
auth-service:sec-ops
cache-service:core-eng
payment-service:fin-ops
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
