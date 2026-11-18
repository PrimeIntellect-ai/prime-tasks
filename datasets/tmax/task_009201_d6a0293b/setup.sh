#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/inventory.json
[
  {"id": "U1", "type": "User", "authorized": true},
  {"id": "U2", "type": "User", "authorized": false},
  {"id": "U3", "type": "User", "authorized": false},
  {"id": "U4", "type": "User", "authorized": false},
  {"id": "S1", "type": "Server"},
  {"id": "S2", "type": "Server"},
  {"id": "S3", "type": "Server"},
  {"id": "DB1", "type": "Database", "contains_pii": true},
  {"id": "DB2", "type": "Database", "contains_pii": false},
  {"id": "DB3", "type": "Database", "contains_pii": true}
]
EOF

    cat << 'EOF' > /home/user/access_edges.csv
source,target
U1,S1
U2,S1
U3,S2
U4,S3
S1,DB1
S1,DB2
S2,DB2
U3,DB3
S2,S1
EOF

    chmod -R 777 /home/user
