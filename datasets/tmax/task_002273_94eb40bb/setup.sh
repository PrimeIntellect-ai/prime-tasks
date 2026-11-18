#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs/web
    mkdir -p /home/user/logs/db
    mkdir -p /home/user/logs/app

    cat << 'EOF' > /home/user/logs/web/access.log
2023-10-01 10.0.0.1 ERROR   Connection timeout...
2023-10-01 10.0.0.1 INFO OK
2023-10-01 10.0.0.2 WARN    Retrying connection!!!
EOF

    cat << 'EOF' > /home/user/logs/db/query.log
2023-10-02 192.168.1.50 DEBUG SELECT * FROM users WHERE age > 20;;;
2023-10-02 192.168.1.50 INFO  Query executed in 0.0001s
EOF

    cat << 'EOF' > /home/user/logs/app/system.log
2023-10-03 127.0.0.1 FATAL System crashoooooout
2023-10-03 127.0.0.1 DEBUG Rebooting         now
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
