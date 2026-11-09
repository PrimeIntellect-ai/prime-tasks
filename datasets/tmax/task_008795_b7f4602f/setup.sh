#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/cloud_costs.csv
ResourceID,Service,Cost
i-1234567890abcdef0,EC2,550.25
vol-0987654321fedcba,EBS,45.00
db-1a2b3c4d5e6f,RDS,1200.50
bucket-finops,S3,600.00
nat-0123456,VPC,150.75
EOF

chmod -R 777 /home/user
