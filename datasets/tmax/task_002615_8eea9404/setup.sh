#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,age
1,25
2,30
3,22
4,35
5,28
EOF

    cat << 'EOF' > /home/user/activity.csv
user_id,hours_active
1,5.5
2,4.0
3,6.2
4,3.1
5,5.0
EOF

    chmod -R 777 /home/user
