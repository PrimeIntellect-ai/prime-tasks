#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
1,Electronics,"Great TV but costs 500\u20ac.   Highly recommended."
2,Books,"Copyright \u00a9 2023. \n\n Good read."
3,Home,"The temperature is 20\u00b0C."
4,Misc,"   Leading and trailing   "
5,EdgeCases,"Look at this: \u2728 magic! \u0041"
EOF
    chmod 644 /home/user/data.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
