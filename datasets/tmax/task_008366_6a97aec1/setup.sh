#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libopenblas-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/

    cat << 'EOF' > /home/user/data/weights.csv
0.5,0.0,1.0,0.0,0.0
0.0,1.0,0.0,0.5,0.0
0.0,0.0,0.0,0.0,1.0
EOF

    cat << 'EOF' > /home/user/data/items.csv
101,1.0,1.0,1.0
102,0.0,2.0,0.0
103,5.0,0.0,0.0
999,invalid,schema
104,2.0,2.0,2.0
EOF

    cat << 'EOF' > /home/user/data/users.csv
1,2.0,1.0,0.0,2.0,1.0
2,10.0,0.0,0.0,0.0,0.0
3,1.0,2.0
4,4.0,2.0,0.0,0.0,2.0
5,bad,data,here,0,0
6,0.0,4.0,0.0,0.0,0.0
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
