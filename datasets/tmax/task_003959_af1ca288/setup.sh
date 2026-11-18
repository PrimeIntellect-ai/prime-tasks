#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deploy_keys
    touch /home/user/deploy_keys/id_ed25519

    cat << 'EOF' > /home/user/network_logs.txt
[2023-10-24 10:15:30] SOURCE:frontend TARGET:auth-api PORT:443 RESULT:SUCCESS
[2023-10-24 10:15:32] SOURCE:payment-service TARGET:redis-cache PORT:6379 RESULT:TIMEOUT
[2023-10-24 10:15:33] SOURCE:payment-service TARGET:db-main PORT:5432 RESULT:SUCCESS
[2023-10-24 10:15:35] SOURCE:inventory-api TARGET:db-inventory PORT:5432 RESULT:TIMEOUT
[2023-10-24 10:15:38] SOURCE:frontend TARGET:payment-service PORT:443 RESULT:SUCCESS
[2023-10-24 10:15:40] SOURCE:user-profile TARGET:auth-api PORT:443 RESULT:TIMEOUT
[2023-10-24 10:15:42] SOURCE:payment-service TARGET:redis-cache PORT:6379 RESULT:TIMEOUT
EOF

    chmod -R 777 /home/user
