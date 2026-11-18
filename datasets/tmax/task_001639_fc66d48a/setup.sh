#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang socat curl gawk grep sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/billing_raw.csv
id,service,region,status,cost
1,EC2,us-east-1,ACTIVE,100.50
2,S3,us-east-1,STOPPED,50.00
3,S3,us-west-2,ACTIVE,20.25
4,RDS,eu-central-1,ACTIVE,200.00
5,EC2,us-east-1,ACTIVE,0.00
6,Lambda,us-east-1,ACTIVE,5.50
7,EC2,us-west-1,ACTIVE,49.50
EOF

    chmod -R 777 /home/user
