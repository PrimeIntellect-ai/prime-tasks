#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
f1,f2,f3,f4,f5
10,100,30,,5000
12,,31,40,5500
,120,33,42,5100
11,110,,41,5200
13,130,32,45,
10,105,30,40,5000
EOF

    chmod -R 777 /home/user
