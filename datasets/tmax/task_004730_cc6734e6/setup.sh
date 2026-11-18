#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /app/sh-graph-query-1.0/bin
    cat << 'EOF' > /app/sh-graph-query-1.0/bin/query_edges.sh
#!/bin/bash
# Bug: logical OR 1 causes it to print everything (implicit cross join over all rows), and missing sort
awk -F, -v id="$1" '{ if ($1 == id || 1) print $2 "," $3 }' edges.csv
EOF
    chmod +x /app/sh-graph-query-1.0/bin/query_edges.sh

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/query_edges_oracle.py
#!/usr/bin/env python3
import sys
import csv

if len(sys.argv) != 2:
    sys.exit(1)
node_id = sys.argv[1]

results = []
try:
    with open('edges.csv', 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row[0] == node_id:
                results.append((int(row[1]), int(row[2])))
except FileNotFoundError:
    pass

results.sort(key=lambda x: (x[0], x[1]))
for r in results:
    print(f"{r[0]},{r[1]}")
EOF
    chmod +x /opt/oracle/query_edges_oracle.py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/edges.csv
1,2,10
1,3,5
2,4,15
3,4,10
1,4,20
EOF

    chmod -R 777 /home/user
