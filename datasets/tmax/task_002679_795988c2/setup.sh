#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/eu.csv
srv-münchen,100,50
srv-londres,101,120
srv-münchen,102,60
srv-münchen,103,70
srv-münchen,104,80
EOF

    cat << 'EOF' > /home/user/configs/asia.tsv
srv-東京	105	200
srv-서울	106	150
srv-東京	107	300
srv-서울	108	250
srv-東京	109	100
srv-東京	110	400
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
