#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiment_data.csv
uid,variant,converted
101,A,1
102,B,0
103,A,0
invalid,A,1
104,C,1
105,B,1
106,B,2
107,A,1
108,B,-1
109,A,0
110,A,1
111,,1
112,B,1
EOF

    chmod -R 777 /home/user
