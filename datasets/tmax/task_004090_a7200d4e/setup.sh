#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libeigen3-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
1.0,2.0,3.0
4.0,NaN,6.0
7.0,8.0,9.0
NaN,1.0,2.0
3.0,4.0,5.0
6.0,7.0,NaN
9.0,1.0,3.0
2.0,5.0,8.0
5.0,NaN,1.0
8.0,2.0,4.0
EOF

    cat << 'EOF' > /home/user/weights.csv
0.5
-0.2
1.1
EOF

    chmod -R 777 /home/user
