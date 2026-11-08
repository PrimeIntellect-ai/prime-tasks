#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/perf_trace.csv
caller_id,callee_id,exec_time_ns
ROOT,A,9000000000.500
ROOT,C,9000000000.500
A,B1,9000000000.100
A,B2,9000000000.200
A,B3,9000000000.300
A,B4,9000000000.400
A,B5,9000000000.500
A,B6,9000000000.600
A,B7,9000000000.700
A,B8,9000000000.800
C,D1,9000000000.100
C,D2,9000000000.200
C,D3,9000000000.300
EOF

    chmod 644 /home/user/perf_trace.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
