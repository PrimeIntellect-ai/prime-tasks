#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron logrotate curl build-essential cargo
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/billing_data/region_a
    mkdir -p /home/user/billing_data/region_b
    mkdir -p /home/user/logs

    # Initialize Rust project
    cd /home/user
    cargo new finops-analyzer

    # Create dummy data
    cat <<EOF > /home/user/billing_data/region_a/ec2.csv
ResourceID,Type,Status,Cost
i-123,ec2,running,10.50
i-124,ec2,idle,5.25
i-125,ec2,IDLE,15.00
EOF

    cat <<EOF > /home/user/billing_data/region_b/rds.csv
ResourceID,Type,Status,Cost
db-1,rds,stopped,0.00
db-2,rds,idle,100.50
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
