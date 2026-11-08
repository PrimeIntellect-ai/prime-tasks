#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph_backup.csv
nodeA,current_status,ACTIVE,100
nodeA,current_status,INACTIVE,50
nodeA,current_status,PENDING,20
nodeB,current_status,INACTIVE,200
nodeB,current_status,ACTIVE,150
user1,manages,nodeA,10
user2,manages,nodeB,10
user3,manages,nodeC,10
nodeC,current_status,ACTIVE,300
nodeC,current_status,ERROR,400
user4,manages,nodeA,12
user5,manages,nodeX,50
EOF

    chmod -R 777 /home/user
