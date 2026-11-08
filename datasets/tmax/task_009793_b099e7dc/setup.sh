#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/backup_deps.csv
source_db,target_db,job_id
db_core,db_auth,job_101
db_core,db_inventory,job_102
db_core,db_shipping,job_103
db_core,db_billing,job_104
db_auth,db_users,job_105
db_auth,db_sessions,job_106
db_auth,db_analytics,job_107
db_inventory,db_catalog,job_108
db_inventory,db_analytics,job_109
db_users,db_profiles,job_110
db_billing,db_invoices,job_111
db_billing,db_analytics,job_112
db_shipping,db_tracking,job_113
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
