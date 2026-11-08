#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_dumps/

    # State A: localhost:5432 (100)
    cat << 'EOF' > /home/user/config_dumps/dump_1600000000.json
{"db_host": "localhost", "db_port": 5432, "max_connections": 100, "extra_key": "ignore"}
EOF

    cat << 'EOF' > /home/user/config_dumps/dump_1600000060.txt
db_host=localhost
db_port=5432
max_connections=100
other=stuff
EOF

    # State B: db.internal:5432 (100) - Change in host
    cat << 'EOF' > /home/user/config_dumps/dump_1600000120.json
{"db_host": "db.internal", "db_port": 5432, "max_connections": 100}
EOF

    cat << 'EOF' > /home/user/config_dumps/dump_1600000180.txt
db_host=db.internal
db_port=5432
max_connections=100
EOF

    # State C: db.internal:5432 (200) - Change in max_connections
    cat << 'EOF' > /home/user/config_dumps/dump_1600000240.json
{"db_host": "db.internal", "db_port": 5432, "max_connections": 200}
EOF

    # State A again: localhost:5432 (100) - Reverted
    cat << 'EOF' > /home/user/config_dumps/dump_1600000300.txt
db_host=localhost
db_port=5432
max_connections=100
EOF

    chown -R user:user /home/user/config_dumps
    chmod -R 777 /home/user
