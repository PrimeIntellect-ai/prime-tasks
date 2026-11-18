#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas networkx

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

cat << 'EOF' > /home/user/setup_data.py
import csv
import os

nodes = [
    (1, 'Person', 'Alice Smith'),
    (2, 'Person', 'Bob Jones'),
    (3, 'Person', 'Charlie Brown'),
    (4, 'Person', 'Diana Prince'),
    (10, 'Company', 'TechCorp'),
    (11, 'Company', 'VentureCapital Inc'),
    (12, 'Company', 'MegaHoldings'),
    (13, 'Company', 'StartupX'),
    (14, 'Company', 'GlobalBank')
]

edges = [
    (1, 10, 'CEO_of'),
    (1, 11, 'sits_on_board'),
    (11, 10, 'invested_in'), # Alice is a match

    (2, 13, 'CEO_of'),
    (2, 12, 'sits_on_board'),
    (12, 13, 'invested_in'), # Bob is a match

    (3, 14, 'CEO_of'),
    (14, 13, 'invested_in'),

    (4, 10, 'sits_on_board'),
    (4, 11, 'sits_on_board'),
    (4, 12, 'sits_on_board'),

    # Adding extra edges to make PageRank interesting
    (14, 11, 'invested_in'),
    (14, 12, 'invested_in'),
    (12, 11, 'invested_in'),
    (10, 11, 'invested_in'),
    (13, 11, 'invested_in')
]

with open('/home/user/data/nodes.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'label', 'name'])
    writer.writerows(nodes)

with open('/home/user/data/edges.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['source', 'target', 'type'])
    writer.writerows(edges)
EOF

python3 /home/user/setup_data.py
rm /home/user/setup_data.py

chmod -R 777 /home/user
