#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/audit_data.jsonl
{"doc_type": "ownership", "parent": "Alpha", "subsidiaries": [{"name": "Beta", "stake": 60}, {"name": "Delta", "stake": 30}]}
{"doc_type": "transaction", "sender": "Beta", "receiver": "Gamma", "amount": 800000, "currency": "USD"}
{"doc_type": "transaction", "sender": "Beta", "receiver": "Gamma", "amount": 300000, "currency": "USD"}
{"doc_type": "transaction", "sender": "Gamma", "receiver": "Alpha", "amount": 1500000, "currency": "USD"}
{"doc_type": "transaction", "sender": "Epsilon", "receiver": "Zeta", "amount": 2000000, "currency": "USD"}
{"doc_type": "ownership", "parent": "Zeta", "subsidiaries": [{"name": "Eta", "stake": 51}]}
{"doc_type": "ownership", "parent": "Eta", "subsidiaries": [{"name": "Theta", "stake": 80}]}
{"doc_type": "transaction", "sender": "Theta", "receiver": "Epsilon", "amount": 1000001, "currency": "USD"}
{"doc_type": "transaction", "sender": "Delta", "receiver": "Omega", "amount": 500000, "currency": "USD"}
{"doc_type": "ownership", "parent": "Omega", "subsidiaries": [{"name": "Psi", "stake": 40}]}
{"doc_type": "transaction", "sender": "Psi", "receiver": "Delta", "amount": 5000000, "currency": "USD"}
EOF

    chmod -R 777 /home/user
