#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/dataset_A.csv
x,y
0,1
1,3
2,5
3,7
EOF

    cat << 'EOF' > /home/user/datasets/dataset_B.csv
x,y
0,0.5
1,2.5
2,5.5
3,6.5
EOF

    cat << 'EOF' > /home/user/datasets/dataset_C.csv
x,y
0,5
1,1
2,8
3,-2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
