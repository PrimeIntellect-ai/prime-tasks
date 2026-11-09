#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/user_metadata.csv
3,22,US
1,25,US
5,28,UK
4,35,CA
2,30,UK
EOF

    cat << 'EOF' > /home/user/user_activity.csv
1,100,5
2,150,10
3,200,2
4,50,0
5,120,8
EOF

    chmod -R 777 /home/user
