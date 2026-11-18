#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc curl
    pip3 install pytest flask

    mkdir -p /home/user/app

    # 1. Create the C file
    cat << 'EOF' > /home/user/app/userhash.c
int compute_hash(int id) {
    return (id * 97) ^ 0x5A;
}
EOF

    # 2. Create the initial database
    sqlite3 /home/user/app/data.db << 'EOF'
CREATE TABLE employees (id INTEGER PRIMARY KEY, full_name TEXT, age INTEGER);
INSERT INTO employees (id, full_name, age) VALUES (1, 'Alice Smith', 30);
INSERT INTO employees (id, full_name, age) VALUES (2, 'Bob Jones', 45);
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
