#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,name,age
1,Alice,25
2,Bob,30
3,Charlie,22
4,Diana,28
EOF

    cat << 'EOF' > /home/user/scores.csv
user_id,score1,score2
1,10,20
2,15,15
4,30,40
5,50,50
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
