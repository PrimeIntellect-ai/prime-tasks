#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor1.txt
1620000005 0.0 0.0 0.0
1620000000 1.0 2.0 3.0
1620000003 10.0 10.0 10.0
1620000002 4.0 5.0 6.0
1620000007 1.0 1.0 1.0
EOF

    cat << 'EOF' > /home/user/sensor2.txt
1620000002 4.0 10.0 6.0
1620000000 1.0 2.0 3.0
1620000005 100.0 100.0 100.0
1620000001 2.0 2.0 2.0
1620000007 1.0 1.0 6.0
EOF

    chmod -R 777 /home/user
