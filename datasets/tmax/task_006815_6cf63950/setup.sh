#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip gawk
    pip3 install pytest

    mkdir -p /tmp/remote_drop
    mkdir -p /home/user/etl_workspace

    cat << 'EOF' > /tmp/remote_drop/run1.csv
transaction_id,receipt_id,status
101,ABCDEF123456,SUCCESS
102,9876543210AB,SUCCESS
103,QWERTYUIOP12,SUCCESS
104,ZXCVBNM09876,FAILED
105,112233445566,SUCCESS
EOF

    cat << 'EOF' > /tmp/remote_drop/run2_retry.csv
transaction_id,receipt_id,status
201,ABCDEF123456,SUCCESS
202,9876543210AC,SUCCESS
203,QWERTYUIOP12,SUCCESS
204,ZXCVBNM09877,SUCCESS
205,112233445588,SUCCESS
206,FFDDEE123456,SUCCESS
EOF

    cd /tmp/remote_drop
    tar -czf etl_exports.tar.gz run1.csv run2_retry.csv
    rm run1.csv run2_retry.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
