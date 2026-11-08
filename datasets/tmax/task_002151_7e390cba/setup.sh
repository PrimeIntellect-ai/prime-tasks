#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /app

    cat << 'EOF' > /home/user/customers.csv
customer_id,name,signup_date
1,Alice,2023-01-01
2,Bob,2023-01-02
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,customer_id,tx_date,amount
1,1,2023-01-05,100.0
2,1,2023-01-10,50.0
3,2,2023-01-06,200.0
EOF

    cat << 'EOF' > /home/user/calls.csv
call_id,customer_id,call_date,duration_seconds
1,1,2023-01-06,300
2,2,2023-01-07,150
EOF

    espeak -w /app/requirements.wav "The API must be secured with the token sierra dash tango dash ninety nine. The rolling sum window should be set to exactly seven days."

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
