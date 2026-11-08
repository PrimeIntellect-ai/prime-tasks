#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/reviews.csv
1,5,Great product! Highly recommend.
2,3,It was okay. Nothing special.
3,5,Amazing, simply amazing.
4,1,Terrible; do not buy!
5,5,Good.
6,4,Pretty decent for the price.
7,5,Love it! Best purchase ever.
8,2,Broke after two days.
EOF
    chmod 644 /home/user/reviews.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
