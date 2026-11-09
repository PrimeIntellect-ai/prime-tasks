#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/export_A.csv
tx_id,user_id,amount,timestamp,retry_flag
T01,U1,100,10,0
T02,U1,-50,11,0
T03,U2,200,10,0
T-06,U1,100,20,0
EOF

    cat << 'EOF' > /home/user/data/export_B.csv
tx_id,user_id,amount,timestamp,retry_flag
T04,U1,50,15,0
T05,U2,300,15,0
T07,U3,50,5,0
T08,U3,50,6,0
T09,U3,50,7,0
EOF

    cat << 'EOF' > /home/user/data/export_retry.csv
tx_id,user_id,amount,timestamp,retry_flag
T01,U1,100,12,1
T03,U2,200,10,1
T08,U3,50,6,2
EOF

    chown -R user:user /home/user/data /home/user/output
    chmod -R 777 /home/user
