#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo gzip jq gawk sed
    pip3 install pytest

    mkdir -p /home/user/legacy_logs
    mkdir -p /home/user/processed_logs

    cat << 'EOF' > /home/user/service_mapping.conf
alpha=payment_svc
beta=auth_svc
gamma=inventory_svc
EOF

    cat << 'EOF' > /home/user/legacy_logs/app_alpha_archive.log
[INFO] 2023-01-01 Service started
[ERROR] 2023-01-02 Payment failed for user 123
Invalid line that should be ignored
[WARN] 2023-01-03 Retry attempt 1
EOF

    cat << 'EOF' > /home/user/legacy_logs/app_beta_archive.log
[INFO] 2023-02-01 Auth service boot
[INFO] 2023-02-01 User admin logged in
EOF

    cat << 'EOF' > /home/user/legacy_logs/app_gamma_archive.log
[ERROR] 2023-03-05 Out of stock item 999
EOF

    gzip /home/user/legacy_logs/*.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
