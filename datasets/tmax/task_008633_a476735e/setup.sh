#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.tsv
1	Alice_Sys	Admin
2	Bob_Dev	Developer
3	Charlie_Ops	Admin
4	Dave_Sec	Security
5	Eve_Root	Admin
6	Frank_Net	Admin
EOF

    cat << 'EOF' > /home/user/edges.tsv
1	2	Execute
1	3	Read
1	4	Execute
3	1	Execute
3	2	Execute
3	4	Execute
3	5	Execute
5	1	Read
5	2	Write
6	1	Execute
6	2	Execute
6	3	Execute
6	4	Execute
6	5	Execute
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
