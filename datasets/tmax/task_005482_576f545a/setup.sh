#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
1,2014,Genetics
2,2015,Genetics
3,2016,Genetics
4,2018,Physics
5,2020,Genetics
6,2015,Genetics
7,2010,Genetics
8,2016,Chemistry
9,2017,Genetics
10,2021,Genetics
EOF

    cat << 'EOF' > /home/user/data/edges.csv
1,2
3,2
4,2
8,2
2,3
4,3
5,3
6,5
7,5
8,5
10,5
1,6
3,6
10,9
4,10
5,10
7,10
1,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
