#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/graph.csv
U1,type,User
U2,type,User
U3,type,User
U4,type,User
R_ADMIN,type,Role
R_USER,type,Role
R_GUEST,type,Role
SYS_DB,type,System
SYS_WEB,type,System
SYS_LOG,type,System
SYS_BACKUP,type,System
U1,assigned_to,R_ADMIN
U2,assigned_to,R_USER
U3,assigned_to,R_GUEST
U4,assigned_to,R_GUEST
R_ADMIN,grants_access,SYS_DB
R_ADMIN,grants_access,SYS_WEB
R_ADMIN,grants_access,SYS_LOG
R_ADMIN,grants_access,SYS_BACKUP
R_USER,grants_access,SYS_WEB
R_USER,grants_access,SYS_LOG
R_GUEST,grants_access,SYS_WEB
EOF

    cat << 'EOF' > /home/user/data/logs.csv
timestamp,user_id,system_id
1690000000,U1,SYS_DB
1690000010,U2,SYS_WEB
1690000020,U3,SYS_WEB
1690000030,U2,SYS_DB
1690000040,U3,SYS_LOG
1690000050,U4,SYS_BACKUP
1690000060,U2,SYS_DB
1690000070,U3,SYS_LOG
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
