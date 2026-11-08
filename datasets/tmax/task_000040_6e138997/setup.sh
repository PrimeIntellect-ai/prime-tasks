#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_metrics.csv
ID,CPU,RAM,DiskIO,Status
1,10.0,20.0,500,OK
2,?,50.0,600,OK
3,80.0,90.0,1500,FAIL
4,invalid,10.0,100,OK
5,90.0,110.0,800,FAIL
6,40.0,?,100,OK
7,50.0,50.0,200,OK
8,95.0,95.0,900,FAIL
9,15.0,15.0,300,OK
10,85.0,85.0,700,FAIL
11,extra,cols,here,1,2,FAIL
12,20.0,20.0,100,UNKNOWN
13,?,105.0,500,FAIL
14,25.0,30.0,200,OK
EOF

    chmod -R 777 /home/user
