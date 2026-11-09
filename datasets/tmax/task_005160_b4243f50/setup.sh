#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,f1,f2,target
1,10,20,0.00
2,15,,0.00
3,20,30,0.00
4,25,NaN,0.00
5,30,40,0.00
EOF

    chmod -R 777 /home/user
