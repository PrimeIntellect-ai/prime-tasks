#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
id,name,department
1,Alice,Engineering
2,Bob,Sales
3,Charlie,Engineering
4,Dave,Engineering
5,Eve,Engineering
6,Frank,HR
EOF

    cat << 'EOF' > /home/user/data/communications.csv
sender_id,receiver_id,message_count
1,2,10
1,3,5
3,1,2
3,4,20
4,5,8
5,1,100
2,6,50
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
