#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/processed/
    cat << 'EOF' > /home/user/processed/data.csv
tx_id,user_id,amount
EOF

    for i in $(seq 1 880); do
        echo "TX$(printf "%04d" $i),100$i,25.50" >> /home/user/processed/data.csv
    done

    for i in $(seq 881 950); do
        echo "TX$(printf "%04d" $i),100$i.0,15.00" >> /home/user/processed/data.csv
    done

    for i in $(seq 951 1000); do
        echo "TX$(printf "%04d" $i),NaN,99.99" >> /home/user/processed/data.csv
    done

    chmod -R 777 /home/user
