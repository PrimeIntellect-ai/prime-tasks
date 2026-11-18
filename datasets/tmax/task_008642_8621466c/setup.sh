#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/data/

    cat << 'EOF' > /home/user/data/entities.dat
101,Alice,Engineering,Senior Developer
102,Bob,Engineering,Manager
103,Charlie,HR,Recruiter
104,David,Engineering,Junior Developer
105,Eve,Sales,Director
106,Frank,Engineering,DevOps
EOF

    cat << 'EOF' > /home/user/data/edges.dat
m1,101,102,1620000000,500
m2,102,104,1620000010,200
m3,101,104,1620000020,300
m4,104,101,1620000030,150
m5,103,101,1620000040,50
m6,101,102,1620000050,100
m7,106,101,1620000060,400
m8,106,102,1620000070,600
m9,104,106,1620000080,150
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
