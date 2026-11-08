#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sequence_signal.csv
pos,exp_val,sim_val
1,7.5,7.5
2,9.5,9.6
3,11.5,11.9
4,13.5,14.5
5,16.5,18.0
6,17.5,19.5
7,19.5,22.0
8,21.5,24.5
9,23.5,27.0
10,25.5,30.0
11,27.5,34.0
12,29.5,39.0
13,31.5,46.0
14,33.5,56.0
15,35.5,70.0
16,37.5,100.0
17,39.5,140.0
18,41.5,190.0
19,43.5,250.0
20,45.5,320.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
