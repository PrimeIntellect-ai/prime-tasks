#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,age,region
1,25,NA
2,17,EU
3,45,AS
4,130,NA
5,50,EU
6,30,SA
8,40,AF
9,22,NA
EOF

    cat << 'EOF' > /home/user/predictions.csv
user_id,score,class_label
1,0.85,1
2,0.90,1
3,1.20,0
4,0.50,0
5,0.45,2
6,0.30,0
7,0.99,1
9,0.77,1
EOF

    chmod -R 777 /home/user
