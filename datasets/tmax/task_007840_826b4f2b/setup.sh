#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget g++ build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    wget -O /home/user/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    cat << 'EOF' > /home/user/data/users.csv
id,name,region
1,Alice,US
2,Bob,UK
3,Charlie,US
4,Diana,CA
5,Eve,UK
6,Frank,AU
EOF

    cat << 'EOF' > /home/user/data/transactions.jsonl
{"tx_id": "t1", "user_id": 1, "amount": 1200.0, "status": "COMPLETED"}
{"tx_id": "t2", "user_id": 2, "amount": 500.0, "status": "COMPLETED"}
{"tx_id": "t3", "user_id": 2, "amount": 600.0, "status": "FAILED"}
{"tx_id": "t4", "user_id": 3, "amount": 100.0, "status": "COMPLETED"}
{"tx_id": "t5", "user_id": 5, "amount": 2000.0, "status": "COMPLETED"}
{"tx_id": "t6", "user_id": 6, "amount": 50.0, "status": "PENDING"}
EOF

    cat << 'EOF' > /home/user/data/network.edges
1 2 10
2 3 5
3 4 2
4 5 8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
