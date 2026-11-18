#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq gawk
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
id,name
1,Alice
2,Bob
3,Charlie
4,David
5,Eve
6,Frank
7,Grace
8,Heidi
EOF

    cat << 'EOF' > /home/user/data/edges.csv
source,target
1,2
1,4
2,3
2,5
4,5
5,6
6,7
3,7
8,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
