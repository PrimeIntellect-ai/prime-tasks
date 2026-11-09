#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/decay_data.csv
t,y
0,5.0000
1,3.2852
2,2.1585
3,1.4182
4,0.9318
5,0.6122
EOF

    chmod -R 777 /home/user
