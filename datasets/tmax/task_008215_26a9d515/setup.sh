#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
x,y
1.0,2.2
2.0,4.1
3.0,6.0
4.0,8.1
5.0,10.2
EOF

    chmod -R 777 /home/user
