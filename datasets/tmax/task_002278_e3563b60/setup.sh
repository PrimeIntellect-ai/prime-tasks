#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install --default-timeout=100 pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/train.csv
ID,X,Y
1,2.5,4.0
2,3.1,1.5
3,7.0,2.2
4,5.5,3.3
5,1.2,8.4
6,9.1,2.0
7,4.4,4.4
8,6.0,1.1
9,3.3,3.3
10,8.2,2.5
11,5.0,5.0
12,2.2,9.1
13,7.5,1.2
14,4.1,4.2
15,6.6,2.3
EOF

    cat << 'EOF' > /home/user/test.csv
ID,X,Y
4,5.5,3.3
7,4.4,4.4
12,2.2,9.1
15,6.6,2.3
16,1.1,1.1
17,2.2,2.2
18,3.3,3.3
EOF

    chmod -R 777 /home/user
