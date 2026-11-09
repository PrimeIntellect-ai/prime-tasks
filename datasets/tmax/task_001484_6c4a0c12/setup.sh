#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/data

    cat << 'EOF' > /app/data/customers.csv
customer_id,name,region
CUST-8924,Alice Smith,North America
CUST-1111,Bob Jones,Europe
EOF

    cat << 'EOF' > /app/data/interactions.csv
ticket_id,customer_id,issue_type,resolution_time
T-01,CUST-8924,Defect,24.5
T-02,CUST-8924,Billing,12.0
T-03,CUST-1111,Defect,48.0
EOF

    cat << 'EOF' > /app/data/purchases.json
{"customer_ref": "CUST-8924", "items": [{"category": "Electronics", "price": 250.0}, {"category": "Books", "price": 15.0}], "transaction_metadata": {"date": "2023-01-01"}}
{"customer_ref": "CUST-8924", "items": [{"category": "Electronics", "price": 150.0}], "transaction_metadata": {"date": "2023-02-01"}}
EOF

    espeak -w /app/vip_call.wav "Hello, I am calling regarding my account, reference ID CUST-8924. I am having issues with my recent purchase in the Electronics category."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
