#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/quotes.csv
timestamp,symbol,bid,ask
2023-10-01T10:00:00Z,AAPL,150.00,150.10
2023-10-01T10:00:00Z,MSFT,300.00,300.20
2023-10-01T10:05:00Z,AAPL,150.05,150.12
2023-10-01T10:08:00Z,TSLA,250.00,250.50
2023-10-01T10:10:00Z,MSFT,300.15,300.25
EOF

    cat << 'EOF' > /home/user/trades.csv
timestamp,symbol,price,volume
2023-10-01T09:59:00Z,AAPL,150.00,50
2023-10-01T10:01:00Z,AAPL,150.05,100
2023-10-01T10:02:00Z,MSFT,300.10,50
2023-10-01T10:06:00Z,AAPL,150.10,200
2023-10-01T10:09:00Z,TSLA,250.25,100
2023-10-01T10:11:00Z,MSFT,300.20,150
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
