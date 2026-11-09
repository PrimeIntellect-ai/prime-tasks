#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    mkdir -p /tmp/backup_gen/config/network

    cat << 'EOF' > /tmp/backup_gen/config/app.json
{
  "app_name": "MyApp",
  "version": "1.0.0",
  "debug": false
}
EOF
    cat << 'EOF' > /tmp/backup_gen/config/database.xml
<database>
  <host>localhost</host>
  <port>5432</port>
</database>
EOF
    cat << 'EOF' > /tmp/backup_gen/config/network/routes.csv
path,target
/api,10.0.0.1
/web,10.0.0.2
EOF

    cd /tmp/backup_gen
    tar -czf /home/user/backups/00_base.tar.gz config

    rm -rf /tmp/backup_gen/*
    mkdir -p /tmp/backup_gen/config
    cat << 'EOF' > /tmp/backup_gen/config/app.json
{
  "app_name": "MyApp",
  "version": "1.1.0",
  "debug": true
}
EOF

    cd /tmp/backup_gen
    tar -czf /home/user/backups/01_inc.tar.gz config

    rm -rf /tmp/backup_gen/*
    mkdir -p /tmp/backup_gen/config/network
    cat << 'EOF' > /tmp/backup_gen/config/database.xml
<database>
  <host>db.internal.corp</host>
  <port>5433</port>
</database>
EOF
    cat << 'EOF' > /tmp/backup_gen/config/network/routes.csv
path,target
/api,10.0.0.1
/web,10.0.0.2
/admin,10.0.0.3
/metrics,10.0.0.4
EOF

    cd /tmp/backup_gen
    tar -czf /home/user/backups/02_inc.tar.gz config

    rm -rf /tmp/backup_gen

    chmod -R 777 /home/user
