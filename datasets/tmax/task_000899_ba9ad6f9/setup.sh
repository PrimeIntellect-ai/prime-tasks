#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,author_name,department
1,Alice,Physics
2,Bob,Physics
3,Charlie,Chemistry
4,Diana,Math
5,Eve,Chemistry
6,Frank,Biology
7,Grace,Biology
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,weight
1,2,5
1,3,2
2,3,1
3,4,3
4,5,4
6,1,2
7,6,8
6,3,5
5,6,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
