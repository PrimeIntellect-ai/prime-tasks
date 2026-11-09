#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk parallel
    pip3 install pytest

    mkdir -p /home/user/raw_data
    cat << 'EOF' > /home/user/raw_data/transactions.csv
timestamp,email,ip,amount,category
1672531200,alice@example.com,192.168.1.45,10.50,Retail
1672531260,bob.smith@domain.org,10.0.0.5,150.00,Tech
1672531320,charlie@work.net,172.16.0.12,20.00,Retail
1672531380,diana@example.com,192.168.1.100,200.00,Tech
1672531440,eve@domain.org,10.0.0.8,15.25,Retail
1672531500,frank@work.net,172.16.0.22,300.00,Tech
1672531560,grace@example.com,192.168.1.50,12.00,Retail
1672531620,heidi@domain.org,10.0.0.9,250.00,Tech
1672531680,ivan@work.net,172.16.0.33,18.50,Retail
1672531740,judy@example.com,192.168.1.60,400.00,Tech
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
