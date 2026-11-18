#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/sys_mount/etc/app1
    mkdir -p /home/user/sys_mount/opt/app2
    mkdir -p /home/user/sys_mount/etc/app3
    mkdir -p /home/user/sys_mount/var/lib/app4

    cat << 'EOF' > /home/user/sys_mount/etc/app1/config.json
{
  "name": "app1",
  "version": "1.2.4",
  "enabled": true
}
EOF

    cat << 'EOF' > /home/user/sys_mount/opt/app2/settings.json
{
  "name": "app2",
  "description": "background worker",
  "version": "2.0.1"
}
EOF

    cat << 'EOF' > /home/user/sys_mount/etc/app3/conf.json
{
  "version": "0.9.9-beta",
  "mode": "strict"
}
EOF

    cat << 'EOF' > /home/user/sys_mount/var/lib/app4/state.json
{
  "status": "running",
  "version": "3.11.0"
}
EOF

    cat << 'EOF' > /home/user/audit.log
BEGIN RECORD
Timestamp: 1690000000
File: /etc/app1/config.json
Action: MODIFIED
Status: SUCCESS
END RECORD
BEGIN RECORD
Timestamp: 1690000010
File: /etc/app3/conf.json
Action: MODIFIED
Status: FAILED
END RECORD
BEGIN RECORD
Timestamp: 1690000020
File: /opt/app2/settings.json
Action: MODIFIED
Status: SUCCESS
END RECORD
BEGIN RECORD
Timestamp: 1690000030
File: /var/lib/app4/state.json
Action: CREATED
Status: SUCCESS
END RECORD
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
