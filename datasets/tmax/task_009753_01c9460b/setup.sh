#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/backup_metadata

    cat << 'EOF' > /home/user/backup_metadata/relational_stats.txt
table: users | rows: 1050
table: orders | rows: 45200
table: products | rows: 840
table: sessions | rows: 990
EOF

    cat << 'EOF' > /home/user/backup_metadata/document_stats.json
{
  "collections": [
    {"name": "user_profiles", "document_count": 1050},
    {"name": "order_receipts", "document_count": 45199},
    {"name": "product_catalog", "document_count": 840},
    {"name": "active_sessions", "document_count": 990}
  ]
}
EOF

    cat << 'EOF' > /home/user/backup_metadata/graph_schema.csv
rel_table,doc_collection
users,user_profiles
orders,order_receipts
products,product_catalog
sessions,active_sessions
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
