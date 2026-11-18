#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_edges.csv
10,20,100
20,30,100
30,40,100
40,50,100
10,15,40
15,25,100
20,10,100
30,20,100
30,60,60
60,70,80
70,80,90
EOF

    chmod 644 /home/user/raw_edges.csv
    chmod -R 777 /home/user
