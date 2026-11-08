#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/billing_logs
    cat << 'EOF' > /home/user/billing_logs/2023-10-01.csv
date,service,resource_id,cost
2023-10-01,EC2,i-12345678,120.50
2023-10-01,RDS,db-87654321,550.00
2023-10-01,S3,bucket-01,5.00
EOF

    cat << 'EOF' > /home/user/billing_logs/2023-10-02.csv
date,service,resource_id,cost
2023-10-02,EC2,i-12345678,600.00
2023-10-02,RDS,db-87654321,550.00
2023-10-02,Lambda,func-99,10.00
EOF

    chmod -R 777 /home/user
