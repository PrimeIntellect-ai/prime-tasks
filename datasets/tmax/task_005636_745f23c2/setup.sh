#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dependencies.tsv
users	type	table
users	scanned_by	scan1
scan1	type	sequential_scan
orders	type	table
orders	scanned_by	scan2
scan2	type	index_scan
products	type	table
products	scanned_by	scan3
scan3	type	sequential_scan
logs	type	table
logs	scanned_by	scan4
scan4	type	sequential_scan
sessions	type	table
sessions	scanned_by	scan5
scan5	type	sequential_scan
metadata	type	table
metadata	scanned_by	scan6
scan6	type	sequential_scan
analytics	type	table
analytics	scanned_by	scan7
scan7	type	index_scan
history	type	table
history	scanned_by	scan8
scan8	type	sequential_scan
EOF

    chmod -R 777 /home/user
