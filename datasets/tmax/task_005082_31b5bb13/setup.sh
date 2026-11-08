#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/transactions.csv
id,timestamp,category,price,user_id
1,2023-01-01T10:00:00,electronics,299.99,101
2,2023-01-01T10:05:00,books,15.50,102
3,2023-01-01T10:10:00,electronics,499.99,103
4,2023-01-01T10:15:00,clothing,45.00,104
5,2023-01-01T10:20:00,electronics,199.99,105
6,2023-01-01T10:25:00,electronics,599.99,106
7,2023-01-01T10:30:00,electronics,299.99,107
8,2023-01-01T10:35:00,electronics,149.99,108
9,2023-01-01T10:40:00,books,25.00,109
10,2023-01-01T10:45:00,electronics,399.99,110
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
