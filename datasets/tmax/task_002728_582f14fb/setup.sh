#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,f1,f2,f3,label
1,2.5,5.1,10.0,0
2,3.0,5.9,8.0,1
3,3.5,7.2,6.0,0
4,4.0,8.0,4.0,1
5,4.5,9.1,2.0,0
EOF

    chmod -R 777 /home/user
