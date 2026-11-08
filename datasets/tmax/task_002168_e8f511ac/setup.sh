#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
X,Y
1.0,2.1
2.0,4.5
?,6.0
3.0,7.1
4.0,9.8
5.0,?
100.0,100.0
6.0,13.2
7.0,16.5
8.0,18.1
-50.0,80.0
9.0,21.0
10.0,23.5
11.0,25.2
12.0,28.0
13.0,30.1
EOF

    chmod -R 777 /home/user
