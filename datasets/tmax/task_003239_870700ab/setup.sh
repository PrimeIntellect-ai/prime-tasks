#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data/project
    mkdir -p /home/user/data/images
    mkdir -p /home/user/backups/incoming/dept_a
    mkdir -p /home/user/backups/incoming/dept_b

    cat << 'EOF' > /home/user/backups/incoming/dept_a/manifest1.json
{
  "backup_id": "job-001",
  "files": [
    "project/app.py",
    "project/../images/logo.png",
    "../../etc/passwd",
    "/home/user/data/project/readme.md"
  ]
}
EOF

    cat << 'EOF' > /home/user/backups/incoming/dept_b/manifest2.json
{
  "backup_id": "job-002",
  "files": [
    "/var/log/syslog",
    "data_dump.sql",
    "/home/user/data/../data/valid_nested/file.txt",
    "/home/user/data_backup/sneaky.txt"
  ]
}
EOF

    cat << 'EOF' > /home/user/backups/incoming/manifest3.json
{
  "backup_id": "job-003",
  "files": [
    "../../../home/user/data/safe.txt",
    "/etc/hosts"
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
