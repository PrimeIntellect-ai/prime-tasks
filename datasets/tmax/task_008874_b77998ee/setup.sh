#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/extracted

    # Create config file
    echo "SOURCE_DIR=/var/old_backups" > /home/user/backup_config.txt

    # Create safe zips
    cd /home/user/backups
    echo "safe data 1" > safe1.txt
    zip backup_safe1.zip safe1.txt
    rm safe1.txt

    echo "safe data 2" > safe2.txt
    zip backup_safe2.zip safe2.txt
    rm safe2.txt

    # Create malicious zips using Python
    python3 -c "
import zipfile
with zipfile.ZipFile('/home/user/backups/backup_malicious.zip', 'w') as zf:
    zf.writestr('../evil.sh', 'echo pwned')
"

    python3 -c "
import zipfile
with zipfile.ZipFile('/home/user/backups/backup_absolute.zip', 'w') as zf:
    zf.writestr('/etc/passwd_overwrite', 'fake:x:0:0:')
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
