#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/etl_task

    cat << 'EOF' > /home/user/etl_task/data.csv
UserID,F1,F2,F3,F4,F5
1,1,0,2,0,1
1,0,1,1,0,0
2,3,0,0,1,1
2,0,0,0,0,1
3,1,1,1,1,1
EOF

    cat << 'EOF' > /home/user/etl_task/matrix.csv
0.5,-0.2
0.1,0.8
-0.3,0.4
0.9,-0.1
0.0,0.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
