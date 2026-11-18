#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/sales.csv
Date,Sales
2023-10-04,200
2023-10-02,150
2023-10-08,350
2023-10-01,100
2023-10-03,
2023-10-07,300
2023-10-05,250
2023-10-06,
EOF

    chmod -R 777 /home/user
