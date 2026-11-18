#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.csv
transaction_id,amount,category
EOF

    for i in $(seq 1 100); do
        echo "$i,$((i * 2 + 5)),A" >> /home/user/transactions.csv
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
