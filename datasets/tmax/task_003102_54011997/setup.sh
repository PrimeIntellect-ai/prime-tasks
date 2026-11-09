#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reads.csv
location,count
5.5,10
15.0,20
25.2,50
35.1,150
41.2,300
43.5,400
44.8,200
47.5,100
55.0,80
65.0,30
75.0,10
85.0,5
95.0,2
EOF

    chmod -R 777 /home/user
