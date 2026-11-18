#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/dataset.csv
transaction_id,cohort,amount
1,Control,150.50
2,Treatment,200.00
3,Control,-50.00
4,Control,
5,Treatment,NaN
6,Treatment,210.25
7,Control,140.20
8,Treatment,-10.00
9,Control,160.30
10,Treatment,205.50
11,Unknown,500.00
12,Control,145.00
13,Treatment,198.75
EOF
    chmod 644 /home/user/dataset.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
