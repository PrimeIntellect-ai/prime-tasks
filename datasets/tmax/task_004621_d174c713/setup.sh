#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,feature_A,feature_B
1,2.5,4.1
2,3.1,5.5
3,4.5,6.8
4,3.0,5.8
5,5.2,8.1
6,4.1,7.2
7,6.0,9.5
8,5.5,8.8
9,7.1,10.2
10,6.8,9.9
11,8.0,11.5
12,7.5,10.8
13,9.2,12.1
14,8.5,11.5
15,10.1,13.5
EOF

    chmod -R 777 /home/user
