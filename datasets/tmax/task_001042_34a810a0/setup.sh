#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest python-Levenshtein

    mkdir -p /home/user/data/crm /home/user/data/transactions /home/user/output

    cat << 'EOF' > /home/user/data/crm/log1.txt
Log entry: Customer Jonathon Doe called about a refund. Reach him at jon.doe@gmail.com.
EOF

    cat << 'EOF' > /home/user/data/crm/log2.txt
Log entry: Customer Alice Smith sent an email from alice123@yahoo.com regarding her subscription.
EOF

    cat << 'EOF' > /home/user/data/crm/log3.txt
Log entry: Customer Bob Brown called to cancel. Reach him at bob.b@corp.com.
EOF

    cat << 'EOF' > /home/user/data/transactions/tx1.json
[{"tx_id": "TX101", "name": "Jonathan Doe", "cc": "1111222233334444"}]
EOF

    cat << 'EOF' > /home/user/data/transactions/tx2.json
[{"tx_id": "TX102", "name": "Alice Smyth", "cc": "5555666677778888"}]
EOF

    cat << 'EOF' > /home/user/data/transactions/tx3.json
[{"tx_id": "TX103", "name": "Robert Brown", "cc": "9999000011112222"}]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
