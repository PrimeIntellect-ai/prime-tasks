#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/profiling_data.csv
MatrixID,ConditionNumber,FactorizationTime_ms,Status
1,1.0e+02,10,SUCCESS
2,1.5e+05,25,SUCCESS
3,2.0e+10,150,SUCCESS
4,5.0e+11,400,SUCCESS
5,1.0e+14,900,FAILED
6,2.0e+15,1500,FAILED
7,5.0e+16,0,FAILED
8,5.0e+11,50,FAILED
EOF

    chmod -R 777 /home/user
