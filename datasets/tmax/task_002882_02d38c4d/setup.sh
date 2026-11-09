#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
tx_id,sender,receiver,amount,timestamp
1,Alice,Bob,100.0,1610000000
2,Bob,Charlie,50.0,1610000010
3,Alice,Dave,25.5,1610000020
4,Alice,Bob,10.0,1610000030
5,Charlie,Alice,200.0,1610000040
6,Bob,Dave,75.0,1610000050
EOF

    chmod -R 777 /home/user
