#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/integrator.csv
step,time,value,residual
1,0.1,1.0,0.5
2,0.2,1.1,-1.5
3,0.3,1.0,2.1
4,0.4,0.9,-0.2
5,0.5,0.9,0.0
6,0.6,1.0,0.5
7,0.7,0.8,-2.5
8,0.8,0.5,-1.2
9,0.9,0.6,0.8
10,1.0,0.8,1.5
11,1.1,0.5,-1.1
12,1.2,0.9,2.0
13,1.3,0.1,-3.0
14,1.4,0.2,0.5
15,1.5,0.3,0.1
16,1.6,0.3,-0.1
17,1.7,0.8,2.2
18,1.8,0.4,-1.5
19,1.9,0.5,1.0
20,2.0,0.4,-0.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
