#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg
    pip3 install pytest

    # Add MongoDB repo and install MongoDB to make it available for the agent
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org

    # Create dummy mongodb package so apt-get install mongodb succeeds if agent tries it
    apt-get install -y equivs
    cat << 'EOF' > mongodb-dummy.control
Section: misc
Priority: optional
Standards-Version: 3.9.2
Package: mongodb
Version: 1:6.0.0
Depends: mongodb-org
Description: Dummy package for mongodb
EOF
    equivs-build mongodb-dummy.control
    dpkg -i mongodb_6.0.0_all.deb || true
    rm mongodb-dummy.control mongodb_6.0.0_all.deb

    pip3 install pymongo networkx

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.jsonl
{"sender": "A", "receiver": "B", "amount": 30}
{"sender": "A", "receiver": "B", "amount": 40}
{"sender": "B", "receiver": "C", "amount": 100}
{"sender": "C", "receiver": "A", "amount": 80}
{"sender": "C", "receiver": "D", "amount": 40}
{"sender": "D", "receiver": "B", "amount": 200}
{"sender": "A", "receiver": "D", "amount": 300}
{"sender": "D", "receiver": "E", "amount": 60}
{"sender": "E", "receiver": "A", "amount": 70}
EOF

    chmod -R 777 /home/user
