#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/exp1.csv
1.0,2.0
2.0,4.0
3.0,4.0
4.0,8.0
EOF

    cat << 'EOF' > /home/user/data/exp2.csv
1.1,10.0
2.1,10.0
3.1,10.0
EOF

    cat << 'EOF' > /home/user/data/exp3.csv
1.0,2.0,3.0
4.0,5.0,6.0
EOF

    cat << 'EOF' > /home/user/data/exp4.csv
1.0,2.0
2.0,abc
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
