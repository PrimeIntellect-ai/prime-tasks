#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc sqlite3 build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
1,Alice,
2,Bob,1
3,Charlie,1
4,David,2
5,Eve,2
6,Frank,3
EOF

    cat << 'EOF' > /home/user/communications.csv
1,2,2023-01-01T10:00:00Z,100
2,3,2023-01-01T10:05:00Z,200
1,4,2023-01-01T10:10:00Z,50
1,2,2023-01-01T10:15:00Z,60
5,1,2023-01-01T11:00:00Z,10
6,5,2023-01-01T11:30:00Z,20
6,4,2023-01-01T12:00:00Z,20
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
