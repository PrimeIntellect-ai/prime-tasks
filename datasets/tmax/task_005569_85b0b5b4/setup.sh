#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv jq
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sales.csv
transaction_id,customer_id,amount
t1,c1,100
t2,c2,200
t3,c1,150
t4,c3,300
t5,c4,50
EOF

    cat << 'EOF' > /home/user/data/customers.csv
customer_id,region_id
c1,r1
c2,r2
c3,r3
c5,r1
EOF

    cat << 'EOF' > /home/user/data/regions.csv
region_id,region_name,tax_rate
r1,North,0.10
r2,South,0.20
r3,East,0.15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
