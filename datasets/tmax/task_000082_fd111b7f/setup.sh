#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
x,y_obs
1.0,1.179509
2.0,1.670245
3.0,2.047278
4.0,2.365448
5.0,2.645000
6.0,2.896791
7.0,3.127402
8.0,3.341398
9.0,3.541908
10.0,3.731215
EOF

    chmod -R 777 /home/user
