#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip g++ make
    pip3 install pytest

    mkdir -p /app/vendor/sqlite3
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user

    wget -qO /tmp/sqlite.zip https://www.sqlite.org/2023/sqlite-amalgamation-3430000.zip
    unzip -q /tmp/sqlite.zip -d /tmp/
    mv /tmp/sqlite-amalgamation-3430000/* /app/vendor/sqlite3/

    cat << 'EOF' > /home/user/Makefile
audit_checker: audit_checker.cpp
	g++ -O2 -std=c++17 -I/app/vendor/sqlite audit_checker.cpp /app/vendor/sqlite/sqlite3.c -o audit_checker
EOF

    cat << 'EOF' > /app/corpus/clean/tx1.json
[{"tx_id": 1, "src": "A", "dst": "B", "amount": 100}, {"tx_id": 2, "src": "A", "dst": "C", "amount": 50}, {"tx_id": 3, "src": "B", "dst": "D", "amount": 100}]
EOF
    cat << 'EOF' > /app/corpus/clean/tx2.json
[{"tx_id": 4, "src": "X", "dst": "Y", "amount": 200}, {"tx_id": 5, "src": "Y", "dst": "Z", "amount": 150}]
EOF

    cat << 'EOF' > /app/corpus/evil/tx1.json
[{"tx_id": 6, "src": "A", "dst": "B", "amount": 100}, {"tx_id": 7, "src": "B", "dst": "C", "amount": 100}, {"tx_id": 8, "src": "C", "dst": "A", "amount": 100}]
EOF
    cat << 'EOF' > /app/corpus/evil/tx2.json
[{"tx_id": 9, "src": "M", "dst": "N", "amount": 500}, {"tx_id": 10, "src": "N", "dst": "O", "amount": 500}, {"tx_id": 11, "src": "O", "dst": "P", "amount": 500}, {"tx_id": 12, "src": "P", "dst": "N", "amount": 500}]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 755 /app
    chmod -R 777 /home/user
