#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,type
U1,User
U2,User
U3,User
R1,Role
R2,Role
R3,Role
R4,Role
S1,System
S2,System
S3,System
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,relation
U1,R1,has_role
U1,R2,has_role
R1,S1,can_request
R2,S1,can_approve
U2,R3,has_role
R3,S2,can_request
R3,S2,can_approve
U3,R4,has_role
R4,S3,can_request
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
