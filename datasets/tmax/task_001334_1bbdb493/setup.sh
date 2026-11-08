#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,parent_id,name,sales
1,,CEO,0
2,1,VP Sales,500
3,1,VP Eng,100
4,2,North,300
5,2,South,400
6,3,Dev,0
7,3,QA,0
8,4,Sales Rep 1,150
9,4,Sales Rep 2,150
EOF

    chmod -R 777 /home/user
