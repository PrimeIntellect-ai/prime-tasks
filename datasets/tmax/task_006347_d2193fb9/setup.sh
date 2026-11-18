#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
id,name
1,START
2,ALPHA
3,BETA
4,GAMMA
5,DELTA
6,END
EOF

    cat << 'EOF' > /home/user/edges.csv
src,dst,weight,timestamp
1,2,10,100
1,2,5,200
2,3,4,150
1,3,15,100
3,6,6,100
2,6,20,100
2,6,8,250
1,4,2,100
4,5,2,100
5,6,12,100
5,6,4,300
EOF

    chmod -R 777 /home/user
