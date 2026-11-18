#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_tx.csv
tx_id,name,email,amount,currency,date
1,Alice Smith,alice@example.com,100.00,USD,2023-10-01
2,Bob Jones,bob.jones@work.org,50.00,EUR,2023-10-01
3,Charlie Brown,charlie@snoopy.com,-20.00,USD,2023-10-02
4,Diana Prince,diana@amazon.net,200.00,GBP,2023-10-02
5,Eve Hacker,eve@evil.com,500.00,JPY,2023-10-03
6,Alice Smith,alice@example.com,50.00,EUR,2023-10-03
7,Frank Castle,frank@punish.com,0.00,USD,2023-10-04
EOF

    chmod -R 777 /home/user
