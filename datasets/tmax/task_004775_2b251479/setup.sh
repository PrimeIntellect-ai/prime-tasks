#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import json

# Generate transactions
transactions = [
    {"tx_id": "T01", "resource": "R01", "state": "GRANTED", "timestamp": 100},
    {"tx_id": "T02", "resource": "R02", "state": "GRANTED", "timestamp": 110},
    {"tx_id": "T01", "resource": "R03", "state": "WAITING", "timestamp": 120},
    {"tx_id": "T02", "resource": "R04", "state": "WAITING", "timestamp": 130},

    # Deadlock 2 (T03 and T04) - earlier timestamp
    {"tx_id": "T03", "resource": "R05", "state": "GRANTED", "timestamp": 10},
    {"tx_id": "T04", "resource": "R06", "state": "GRANTED", "timestamp": 20},
    {"tx_id": "T03", "resource": "R07", "state": "WAITING", "timestamp": 30},
    {"tx_id": "T04", "resource": "R08", "state": "WAITING", "timestamp": 40},

    # Deadlock 3 (T05 and T06)
    {"tx_id": "T05", "resource": "R09", "state": "GRANTED", "timestamp": 200},
    {"tx_id": "T06", "resource": "R10", "state": "GRANTED", "timestamp": 210},
    {"tx_id": "T05", "resource": "R11", "state": "WAITING", "timestamp": 220},
    {"tx_id": "T06", "resource": "R12", "state": "WAITING", "timestamp": 230},

    # Deadlock 4 (T07 and T08)
    {"tx_id": "T07", "resource": "R13", "state": "GRANTED", "timestamp": 50},
    {"tx_id": "T08", "resource": "R14", "state": "GRANTED", "timestamp": 60},
    {"tx_id": "T07", "resource": "R15", "state": "WAITING", "timestamp": 70},
    {"tx_id": "T08", "resource": "R16", "state": "WAITING", "timestamp": 80},

    # Deadlock 5 (T09 and T10)
    {"tx_id": "T09", "resource": "R17", "state": "GRANTED", "timestamp": 300},
    {"tx_id": "T10", "resource": "R18", "state": "GRANTED", "timestamp": 310},
    {"tx_id": "T09", "resource": "R19", "state": "WAITING", "timestamp": 320},
    {"tx_id": "T10", "resource": "R20", "state": "WAITING", "timestamp": 330},

    # Deadlock 6 (T11 and T12) - should be excluded due to pagination
    {"tx_id": "T11", "resource": "R21", "state": "GRANTED", "timestamp": 400},
    {"tx_id": "T12", "resource": "R22", "state": "GRANTED", "timestamp": 410},
    {"tx_id": "T11", "resource": "R23", "state": "WAITING", "timestamp": 420},
    {"tx_id": "T12", "resource": "R24", "state": "WAITING", "timestamp": 430},
]

with open('/home/user/tx_locks.json', 'w') as f:
    json.dump(transactions, f, indent=2)

# Generate graph
graph = [
    "<R03> <dependsOn> <R02> .",
    "<R04> <dependsOn> <R01> .",

    "<R07> <dependsOn> <R06> .",
    "<R08> <dependsOn> <R05> .",

    "<R11> <dependsOn> <R10> .",
    "<R12> <dependsOn> <R09> .",

    "<R15> <dependsOn> <R14> .",
    "<R16> <dependsOn> <R13> .",

    "<R19> <dependsOn> <R18> .",
    "<R20> <dependsOn> <R17> .",

    "<R23> <dependsOn> <R22> .",
    "<R24> <dependsOn> <R21> .",
]

with open('/home/user/resource_graph.nt', 'w') as f:
    for line in graph:
        f.write(line + "\n")
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
