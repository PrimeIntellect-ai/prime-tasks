#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/users.csv
user_id,user_name
U001,Alice Smith
U002,Bob Jones
U003,Charlie Brown
U004,Diana Prince
U005,Eve Davis
EOF

    cat << 'EOF' > /home/user/audit_data/roles.csv
role_id,role_name
R100,Teller
R101,Senior Teller
R102,Branch Manager
R103,Loan Officer
R104,Auditor
R105,Clerk
EOF

    cat << 'EOF' > /home/user/audit_data/user_roles.csv
user_id,role_id
U001,R100
U001,R105
U002,R101
U003,R102
U004,R103
U005,R104
U005,R101
EOF

    cat << 'EOF' > /home/user/audit_data/role_hierarchy.csv
parent_role_id,child_role_id
R101,R100
R102,R101
R102,R103
R105,R104
EOF

    cat << 'EOF' > /home/user/audit_data/role_permissions.csv
role_id,permission_name
R100,FUNDS_INITIATE
R100,VIEW_BALANCE
R103,FUNDS_APPROVE
R103,VIEW_LOANS
R104,VIEW_AUDIT_LOG
R105,FUNDS_APPROVE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
