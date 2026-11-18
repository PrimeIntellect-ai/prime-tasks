#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/relational.csv
cust_id,ltv,region
C001,600,NA
C002,400,EU
C003,1200,APAC
C004,800,NA
C005,500,EU
C006,1000,APAC
EOF

    cat << 'EOF' > /home/user/data/graph.json
[
  {"node_id": "C001", "page_rank": 0.20, "community": 1},
  {"node_id": "C002", "page_rank": 0.50, "community": 1},
  {"node_id": "C003", "page_rank": 0.10, "community": 2},
  {"node_id": "C004", "page_rank": 0.30, "community": 2},
  {"node_id": "C005", "page_rank": 0.15, "community": 3},
  {"node_id": "C006", "page_rank": 0.25, "community": 1}
]
EOF

    cat << 'EOF' > /home/user/data/documents.jsonl
{"_id": "C001", "metadata": {"is_active": true, "loyalty_tier": "gold"}}
{"_id": "C002", "metadata": {"is_active": true, "loyalty_tier": "silver"}}
{"_id": "C003", "metadata": {"is_active": true, "loyalty_tier": "platinum"}}
{"_id": "C004", "metadata": {"is_active": false, "loyalty_tier": "gold"}}
{"_id": "C005", "metadata": {"is_active": true, "loyalty_tier": "bronze"}}
{"_id": "C006", "metadata": {"is_active": true, "loyalty_tier": "platinum"}}
EOF

    cat << 'EOF' > /home/user/.expected_unified_results.csv
Customer_ID,Region,Loyalty_Tier,Score
C006,APAC,platinum,250.00
C001,NA,gold,120.00
C005,EU,bronze,75.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
