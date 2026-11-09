#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    mkdir -p /home/user/source_backup/config
    mkdir -p /home/user/source_backup/system

    cat << 'EOF' > /home/user/source_backup/config/.env
APP_RESTORE_MODE=dry_run_validation
DB_HOST=localhost
DB_PORT=5432
EOF

    cat << 'EOF' > /home/user/source_backup/system/passwd.mock
root:x:0:0:root:/root:/bin/bash
svc_app:x:1001:2001:App Service User:/home/svc_app:/bin/bash
bkp_admin:x:1002:2002:Backup Administrator:/home/bkp_admin:/bin/bash
EOF

    cat << 'EOF' > /home/user/source_backup/system/group.mock
root:x:0:
app_group:x:2001:
bkp_operators:x:2002:
EOF

    cd /home/user/source_backup
    tar -czvf /home/user/backups/app_backup_latest.tar.gz config system
    cd /home/user
    rm -rf /home/user/source_backup

    touch /home/user/.bashrc

    chmod -R 777 /home/user
