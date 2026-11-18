#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.csv
1,2,3,4,5,6,7,8,9,10
10,20,30,40,50,60,70,80,90,100
,,3,4,,6,7,,9,
1,-1,2,-2,3,-3,4,-4,5,-5
0,0,0,0,0,0,0,0,0,0
1000,,2000,,3000,,4000,,5000,
EOF

    chmod -R 777 /home/user
