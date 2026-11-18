#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/backup
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/backup/nodes.csv
id,label
1,User
2,User
3,User
4,Post
5,Post
6,User
7,Page
EOF

    cat << 'EOF' > /home/user/backup/edges.csv
source,target,type
1,2,KNOWS
2,3,KNOWS
3,4,LIKES
2,4,LIKES
1,5,LIKES
6,2,KNOWS
6,7,LIKES
1,6,KNOWS
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
