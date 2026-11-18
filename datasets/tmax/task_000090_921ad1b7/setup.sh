#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/held_locks.csv
pid,table_name
101,users
102,orders
103,inventory
104,billing
105,logs
106,sessions
107,audit
108,metrics
109,backups
110,configurations
111,cache
112,tokens
EOF

    cat << 'EOF' > /home/user/waiting_locks.csv
pid,table_name
101,audit
102,inventory
103,billing
104,sessions
105,users
106,metrics
107,orders
108,backups
109,configurations
110,cache
111,users
112,inventory
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
