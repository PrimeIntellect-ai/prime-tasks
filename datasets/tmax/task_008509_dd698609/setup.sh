#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    mkdir -p /home/user/server_configs/region_us
    mkdir -p /home/user/server_configs/region_eu/app1

    cat << 'EOF' > /home/user/server_configs/region_us/db_config.JSON
{
  "server_id": "us-db-01",
  "status": "deprecated",
  "port": 5432
}
EOF

    cat << 'EOF' > /home/user/server_configs/region_us/web_config.JSON
{
  "server_id": "us-web-01",
  "status": "active",
  "port": 80
}
EOF

    cat << 'EOF' > /home/user/server_configs/region_eu/app1/settings.XML
<config>
  <status>active</status>
</config>
EOF

    cat << 'EOF' > /home/user/server_configs/region_eu/app1/legacy_cfg.JSON
{
  "server_id": "eu-app-01",
  "status": "deprecated",
  "notes": "migrate soon"
}
EOF

    cat << 'EOF' > /home/user/server_configs/users.CSV
id,name
1,admin
EOF

    cd /home/user
    tar --listed-incremental=/home/user/backup.snar -czf /home/user/full_backup.tar.gz server_configs
    sleep 2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
