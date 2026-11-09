#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk tar gzip
    pip3 install pytest

    mkdir -p /home/user/events

    cat << 'EOF' > /home/user/events/log_a.csv
u1,click,100,1620000000
u2,view,,1620000001
u1,scroll,200,1620000002
u3,click,-50,1620000003
u5,scroll,4000,1620000010
EOF

    cat << 'EOF' > /home/user/events/log_b.csv
u2,click,150,1620000004
u3,view,6000,1620000005
u1,click,50,1620000006
u4,view,0,1620000007
u5,click,1000,1620000011
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
