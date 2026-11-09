#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/archives

    # Create corrupted archives
    head -c 1024 /dev/urandom > /home/user/archives/backup_v1.tar.gz
    head -c 1024 /dev/urandom > /home/user/archives/backup_v3.tar.gz

    # Create changelog.txt
    cat << 'EOF' > /tmp/changelog.txt
BEGIN_CHANGE
Author: admin
Date: 2023-10-01
Modified:
  /etc/mysql/my.cnf
  /etc/hosts
END_CHANGE
BEGIN_CHANGE
Author: deploy_bot
Date: 2023-10-02
Modified:
  /etc/nginx/nginx.conf
  /opt/app/config.yaml
END_CHANGE
BEGIN_CHANGE
Author: sysadmin
Date: 2023-10-04
Modified:
  /var/log/syslog
END_CHANGE
BEGIN_CHANGE
Author: deploy_bot
Date: 2023-10-05
Modified:
  /etc/redis/redis.conf
  /opt/app/config.yaml
  /etc/cron.d/backup
END_CHANGE
EOF

    # Create valid archive
    cd /tmp
    tar -czf /home/user/archives/backup_v2.tar.gz changelog.txt
    rm /tmp/changelog.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
