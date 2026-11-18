#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,f1,f2,f3,f4
1,0.5,0.2,0.1,0.8
2,0.1,0.9,0.2,0.0
3,0.0,0.0,0.9,0.3
4,0.7,0.7,0.1,0.1
EOF

    cat << 'EOF' > /home/user/items.csv
item_id,f1,f2,f3,f4
101,0.8,0.1,0.0,0.2
102,0.1,0.8,0.1,0.0
103,0.0,0.1,0.9,0.1
104,0.2,0.2,0.1,0.9
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/users.csv /home/user/items.csv
    chmod -R 777 /home/user
