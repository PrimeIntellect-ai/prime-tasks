#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/users.csv
user_id,username
1,alice
2,bob
3,charlie
4,diana
EOF

    cat << 'EOF' > /home/user/audit_data/user_roles.csv
user_id,role_id
1,R1
2,R2
3,R1
3,R3
4,R4
EOF

    cat << 'EOF' > /home/user/audit_data/roles.csv
role_id,role_name
R1,dev
R2,qa
R3,sysadmin
R4,guest
EOF

    cat << 'EOF' > /home/user/audit_data/role_access.csv
role_id,system_id,permission_level
R1,SYS_A,read
R1,SYS_B,admin
R2,SYS_A,read
R3,SYS_A,admin
R3,SYS_C,admin
R3,SYS_D,admin
R4,SYS_E,read
EOF

    cat << 'EOF' > /home/user/audit_data/legacy_access.csv
r_id,sys,perm
R1,SYS_Z,read
EOF

    chmod -R 777 /home/user
