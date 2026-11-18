#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/access_graph.csv
USR_Alice,GRP_Admin
USR_Bob,GRP_Dev
USR_Charlie,GRP_Guest
USR_Diana,GRP_Dev
GRP_Admin,SRV_Main_DB
GRP_Admin,SRV_App1
GRP_Dev,SRV_App1
GRP_Guest,SRV_Public
SRV_App1,SRV_Backup_DB
SRV_Main_DB,SRV_Core_Auth
USR_Eve,SRV_Core_Auth
EOF

    cat << 'EOF' > /home/user/restricted_systems.csv
SRV_Main_DB
SRV_Backup_DB
SRV_Core_Auth
EOF

    chmod -R 777 /home/user
