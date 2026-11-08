#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,department
A,Sales
B,Engineering
C,HR
D,Engineering
E,Sales
EOF

    cat << 'EOF' > /home/user/edges.csv
src,dst,bytes
A,B,100
A,C,150
B,D,500
B,E,200
C,A,50
D,A,300
D,B,100
D,C,100
E,A,400
A,E,250
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
