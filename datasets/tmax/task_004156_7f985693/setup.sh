#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
tx_id,timestamp,sender,receiver,amount
1,2023-01-01,Alice,Bob,100.0
2,2023-01-02,Alice,Charlie,150.0
3,2023-01-03,Alice,Dave,50.0
4,2023-01-04,Alice,Eve,200.0
5,2023-01-01,Bob,Charlie,300.0
6,2023-01-02,Bob,Alice,300.0
7,2023-01-03,Bob,Dave,300.0
8,2023-01-01,Charlie,Alice,500.0
9,2023-01-02,Dave,Eve,10.0
10,2023-01-03,Dave,Alice,10.0
11,2023-01-04,Dave,Alice,10.0
EOF

    chmod -R 777 /home/user
