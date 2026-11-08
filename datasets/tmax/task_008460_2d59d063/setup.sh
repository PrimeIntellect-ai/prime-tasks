#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/measurements.csv
1,2.5,OK
2,-1.0,OK
A,3.0,OK
3,4.0,FAIL
-1,5.0,OK
4,1.5,OK
5,text,OK
EOF

    chmod -R 777 /home/user
