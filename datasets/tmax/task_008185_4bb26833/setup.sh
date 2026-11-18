#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_raw.tsv
hello world	data
testing the new pipeline	ETL process works
short	very long sentence here
a b c d e	f g
data engineering	data science task
EOF

    chmod -R 777 /home/user
