#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sales.csv
sqft,price
1500,310000
2000,390000
invalid,500000
1200,250000
1800,"360,000"
2500,510000
1600,310000
2100,
  1750  ,  350000  
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
