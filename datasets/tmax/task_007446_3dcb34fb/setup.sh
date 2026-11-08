#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/server_data/logs
    mkdir -p /home/user/server_data/conf
    mkdir -p /home/user/server_data/temp

    cat << 'EOF' > /home/user/server_data/backup_plan.json
{
  "targets": [
    {
      "file": "logs/access.csv",
      "redact": "ipv4"
    },
    {
      "file": "conf/settings.xml",
      "redact": "none"
    },
    {
      "file": "logs/system.log",
      "redact": "ipv4"
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/server_data/logs/access.csv
timestamp,ip_address,status
2023-10-01T10:00:00Z,192.168.1.50,200
2023-10-01T10:05:00Z,10.0.0.15,404
2023-10-01T10:10:00Z,172.16.254.1,500
EOF

    cat << 'EOF' > /home/user/server_data/conf/settings.xml
<?xml version="1.0"?>
<config>
  <database>
    <host>db.internal.local</host>
    <port>5432</port>
  </database>
</config>
EOF

    cat << 'EOF' > /home/user/server_data/logs/system.log
System boot initiated.
Network interface eth0 configured with 192.168.100.22.
Connecting to external API at 203.0.113.5.
EOF

    cat << 'EOF' > /home/user/server_data/conf/secrets.txt
secret password 123
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
