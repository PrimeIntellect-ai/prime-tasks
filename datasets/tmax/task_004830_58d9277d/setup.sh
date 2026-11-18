#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/backups/services.csv
service_id,service_name,team_owner
S1,AuthService,TeamAlpha
S2,BillingService,TeamBeta
S3,EmailService,TeamAlpha
S4,ReportingService,TeamGamma
S5,InventoryService,TeamBeta
EOF

    cat << 'EOF' > /home/user/backups/endpoints.jsonl
{"service_id": "S1", "endpoints": ["/login", "/logout"]}
{"service_id": "S2", "endpoints": ["/pay", "/invoice", "/refund"]}
{"service_id": "S3", "endpoints": ["/send"]}
{"service_id": "S4", "endpoints": ["/report/daily", "/report/weekly"]}
{"service_id": "S5", "endpoints": ["/stock", "/reserve"]}
EOF

    cat << 'EOF' > /home/user/backups/dependencies.json
[
  {"source": "S2", "target": "S1"},
  {"source": "S2", "target": "S3"},
  {"source": "S1", "target": "S3"},
  {"source": "S4", "target": "S1"},
  {"source": "S4", "target": "S2"},
  {"source": "S5", "target": "S1"},
  {"source": "S5", "target": "S4"}
]
EOF

    chmod -R 777 /home/user
