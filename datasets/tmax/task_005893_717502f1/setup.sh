#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/tx_data.json
[
  {
    "tx_id": "TX_001",
    "queries": [
      "MATCH (n:User {uid: 105}) SET n.status = 'updated'",
      "MATCH (n:User {uid: 210}) SET n.status = 'updated'"
    ]
  },
  {
    "tx_id": "TX_002",
    "queries": [
      "MATCH (n:User {uid: 301}) SET n.status = 'updated'",
      "MATCH (n:User {uid: 405}) SET n.status = 'updated'"
    ]
  },
  {
    "tx_id": "TX_003",
    "queries": [
      "MATCH (n:User {uid: 882}) SET n.status = 'updated'",
      "MATCH (n:User {uid: 512}) SET n.status = 'updated'"
    ]
  },
  {
    "tx_id": "TX_004",
    "queries": [
      "MATCH (n:User {uid: 610}) SET n.status = 'updated'",
      "MATCH (n:User {uid: 615}) SET n.status = 'updated'"
    ]
  },
  {
    "tx_id": "TX_005",
    "queries": [
      "MATCH (n:User {uid: 512}) SET n.status = 'updated'",
      "MATCH (n:User {uid: 882}) SET n.status = 'updated'"
    ]
  }
]
EOF

    chmod -R 777 /home/user
