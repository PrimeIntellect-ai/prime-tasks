#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
X,Y
1.2,3.4
2.1,2.0
3.3,1.5
4.0,0.5
1.5,2.2
2.8,1.8
0.5,4.4
3.1,1.1
2.2,2.2
1.9,3.0
EOF

    chmod -R 777 /home/user
