#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml xmltodict

    mkdir -p /home/user/app_configs /home/user/backup

    cat << 'EOF' > /home/user/app_configs/db.json
{
  "host": "localhost",
  "port": 5432,
  "user": "admin_user",
  "password": "supersecretpassword"
}
EOF

    cat << 'EOF' > /home/user/app_configs/server.ini
[http]
port = 8080
bind = 0.0.0.0

[ssl]
enabled = true
cert = /etc/ssl/cert.pem
EOF

    cat << 'EOF' > /home/user/app_configs/metrics.xml
<?xml version="1.0" encoding="UTF-8"?>
<metrics>
    <interval>60</interval>
    <enabled>true</enabled>
    <endpoint>/metrics</endpoint>
</metrics>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
