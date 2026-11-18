#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sequence_data.csv
SeqID,T0,T1,T2,T3,T4
SEQ_001,10.5,8.2,6.5,5.1,4.0
SEQ_002,2.1,2.5,2.0,1.9,2.2
SEQ_003,100.0,60.6,36.7,22.3,13.5
SEQ_004,5.0,5.0,5.0,5.0,5.0
SEQ_005,-10.0,-6.0,-3.6,-2.2,-1.3
SEQ_006,12.0,11.5,10.0,9.5,8.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
