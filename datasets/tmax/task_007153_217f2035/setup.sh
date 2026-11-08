#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories and initial data
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
id,username
1,aaron
2,bob
3,charlie
4,david
5,eve
6,frank
7,grace
EOF

    cat << 'EOF' > /home/user/data/connections.csv
user1_id,user2_id
1,2
1,3
2,3
4,1
5,1
6,2
7,2
EOF

    # Set permissions
    chmod -R 777 /home/user
