#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy matplotlib

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/data.csv
value
1.2
2.3
1.5
NaN
100.0
-1.0
1.8
NaN
2.1
1.9
-50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
