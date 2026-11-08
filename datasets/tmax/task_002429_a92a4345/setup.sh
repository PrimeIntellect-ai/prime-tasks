#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rsync
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/old_projects/proj_alpha
    mkdir -p /home/user/old_projects/proj_beta/sub_dir
    mkdir -p /home/user/backup_drive/projects_backup/proj_alpha
    mkdir -p /home/user/backup_drive/projects_backup/proj_beta

    # Create files
    cat << 'EOF' > /home/user/old_projects/proj_alpha/users.csv
id,username,role
1,admin,superuser
2,bob,editor
EOF

    cat << 'EOF' > /home/user/old_projects/proj_beta/settings.json
{"theme": "dark"}
EOF

    cat << 'EOF' > /home/user/old_projects/proj_beta/sub_dir/metrics.csv
date,clicks,views
2023-01-01,50,1000
2023-01-02,75,1200
EOF

    cat << 'EOF' > /home/user/backup_drive/projects_backup/proj_beta/settings.json
{"theme": "dark"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
