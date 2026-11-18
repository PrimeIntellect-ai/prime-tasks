#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,value,score
1,10.5,80
2,-5.0,90
3,12.1,NaN
4,15.2,
5,3.14,100
6,42.0,85
7,-0.01,70
8,0.0,NA
9,99.9,10
EOF

    chmod -R 777 /home/user
