#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/employees.csv
email,department
alice@company.com,Engineering
bob@company.com,Engineering
charlie@company.com,Sales
diana@company.com,Sales
eve@company.com,Marketing
frank@company.com,Marketing
grace@company.com,Engineering
EOF

    cat << 'EOF' > /home/user/data/interactions.csv
timestamp,actor_email,target_email,interaction_type,metric_value
2023-10-01,alice@company.com,bob@company.com,code_review,2
2023-10-01,charlie@company.com,bob@company.com,meeting,10
2023-10-02,bob@company.com,alice@company.com,email,5
2023-10-03,diana@company.com,charlie@company.com,meeting,15
2023-10-03,eve@company.com,frank@company.com,email,20
2023-10-04,frank@company.com,eve@company.com,meeting,5
2023-10-04,grace@company.com,alice@company.com,code_review,3
2023-10-05,alice@company.com,charlie@company.com,email,10
2023-10-05,bob@company.com,grace@company.com,meeting,30
2023-10-06,charlie@company.com,diana@company.com,email,2
2023-10-06,eve@company.com,bob@company.com,email,15
EOF

    chmod -R 777 /home/user
