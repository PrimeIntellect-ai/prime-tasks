#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/org_events.csv
event_id,timestamp,employee,manager,event_type
1,1620000000,EMP_1,CEO,UPDATE
2,1620000100,EMP_8,EMP_1,UPDATE
3,1620000200,EMP_404,EMP_8,UPDATE
4,1620000300,EMP_2,EMP_1,UPDATE
5,1620000400,EMP_99,CEO,UPDATE
6,1620000500,EMP_8,EMP_1,DELETE
7,1620000600,EMP_404,EMP_2,UPDATE
8,1620000700,EMP_2,EMP_99,UPDATE
9,1620000800,EMP_33,EMP_404,UPDATE
10,1620000900,EMP_2,EMP_1,UPDATE
11,1620001000,EMP_1,EMP_99,UPDATE
12,1620001100,EMP_1,CEO,UPDATE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
