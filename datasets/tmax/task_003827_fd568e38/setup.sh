#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/schema.txt
Nodes: Paper, Author, Institution
Edges:
Paper -> CITES -> Paper
Author -> WROTE -> Paper
Author -> AFFILIATED_WITH -> Institution
EOF

    cat << 'EOF' > /home/user/dataset.csv
P1,Paper,P2,Paper,CITES
A1,Author,P1,Paper,WROTE
A2,Author,I1,Institution,AFFILIATED_WITH
P2,Paper,A1,Author,CITES
A1,Author,P2,Paper,READS
I1,Institution,P1,Paper,WROTE
A3,Author,P3,Paper,WROTE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
