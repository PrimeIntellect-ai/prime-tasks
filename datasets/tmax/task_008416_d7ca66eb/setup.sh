#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
1,25,85.5
2,30,90.0
3,,88.2
4,22,76.4
5,abc,99.9
6,40,92.1
7,35,81.0
8,28,89.5
9,33,
10,29,84.3
11,45,95.2
12,21,78.8
13,50,88.8
14,26,not_a_float
15,31,91.4
EOF

    chmod -R 777 /home/user
