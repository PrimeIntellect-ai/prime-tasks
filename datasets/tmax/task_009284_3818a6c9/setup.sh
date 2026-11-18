#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
1.2,3.4,5.6
2.5,4.1,6.8
3.1,5.5,7.2
4.8,6.2,8.9
5.0,7.0,9.1
6.3,8.4,10.5
7.2,9.1,11.2
8.5,10.6,12.8
9.1,11.5,13.4
10.4,12.0,14.7
EOF

    chmod -R 777 /home/user
