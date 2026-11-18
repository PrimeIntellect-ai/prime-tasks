#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/network.csv
source,target
Alice,Bob
Alice,David
Alice,George
Bob,Charlie
David,Eve
Eve,Alice
Frank,Alice
Bob,Frank
George,Bob
EOF

    chmod -R 777 /home/user
