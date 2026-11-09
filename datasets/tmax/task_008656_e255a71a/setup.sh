#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,department,clearance_level
E_VENDOR,Vendor Acc,External,1
E001,Alice,HR,2
E002,Bob,IT,3
E003,Charlie,Finance,4
E004,David,Engineering,3
E005,Eve,Engineering,5
E006,Frank,IT,2
EOF

    cat << 'EOF' > /home/user/access_logs.jsonl
{"event_id": "e1", "grantor_id": "E_VENDOR", "grantee_id": "E001"}
{"event_id": "e2", "grantor_id": "E_VENDOR", "grantee_id": "E002"}
{"event_id": "e3", "grantor_id": "E001", "grantee_id": "E006"}
{"event_id": "e4", "grantor_id": "E002", "grantee_id": "E003"}
{"event_id": "e5", "grantor_id": "E002", "grantee_id": "E004"}
{"event_id": "e6", "grantor_id": "E002", "grantee_id": "E005"}
{"event_id": "e7", "grantor_id": "E005", "grantee_id": "E006"}
{"event_id": "e8", "grantor_id": "E005", "resource_id": "R_SECURE_PAYMENTS"}
{"event_id": "e9", "grantor_id": "E005", "resource_id": "R_DEV_DB"}
{"event_id": "e10", "grantor_id": "E005", "grantee_id": "E001"}
{"event_id": "e11", "grantor_id": "E005", "grantee_id": "E002"}
{"event_id": "e12", "grantor_id": "E004", "resource_id": "R_SECURE_PAYMENTS"}
{"event_id": "e13", "grantor_id": "E003", "grantee_id": "E005"}
{"event_id": "e14", "grantor_id": "E006", "grantee_id": "E001"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
