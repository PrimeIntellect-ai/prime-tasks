#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metrics.csv
ID,CPU,Memory,Response_Time,Const1,Const2,Status
1,50.5,60.2,120,42,10,OK
2,55.0,65.0,135,42,10,OK
3,NaN,70.1,140,42,10,OK
4,60.2,70.5,150,42,10,ERROR
5,45.1,55.1,110,42,10,OK
6,48.0,58.0,115,42,10,OK
7,62.5,72.3,160,42,10,OK
8,58.9,68.9,145,42,10,OK
9,40.5,50.5,100,42,10,OK
10,65.2,75.1,170,42,10,OK
EOF

    chmod -R 777 /home/user
