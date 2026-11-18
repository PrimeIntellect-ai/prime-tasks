#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo curl gnupg nodejs npm
    pip3 install pytest networkx pymongo

    # Install MongoDB 7.0 from official repository
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update && apt-get install -y mongodb-org || true

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    cat << 'EOF' > /home/user/raw_transactions.json
[
  {"tx_id": "t1", "from_acct": "ACCT_START", "to_acct": "ACCT_A", "amount": 1500},
  {"tx_id": "t2", "from_acct": "ACCT_START", "to_acct": "ACCT_A", "amount": 2000},
  {"tx_id": "t3", "from_acct": "ACCT_A", "to_acct": "ACCT_B", "amount": 4000},
  {"tx_id": "t4", "from_acct": "ACCT_B", "to_acct": "ACCT_TARGET", "amount": 3000},
  {"tx_id": "t5", "from_acct": "ACCT_START", "to_acct": "ACCT_TARGET", "amount": 500},
  {"tx_id": "t6", "from_acct": "ACCT_START", "to_acct": "ACCT_C", "amount": 5000},
  {"tx_id": "t7", "from_acct": "ACCT_C", "to_acct": "ACCT_D", "amount": 6000},
  {"tx_id": "t8", "from_acct": "ACCT_D", "to_acct": "ACCT_TARGET", "amount": 1200},
  {"tx_id": "t9", "from_acct": "ACCT_X", "to_acct": "ACCT_Y", "amount": 15000},
  {"tx_id": "t10", "from_acct": "ACCT_C", "to_acct": "ACCT_TARGET", "amount": 2500}
]
EOF

    chmod -R 777 /home/user
