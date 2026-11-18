#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_restore/data
    cat << 'EOF' > /home/user/app_restore/config.ini
[General]
AppName=BackupTester
Version=1.0.4

[Security]
AllowAutomatedRestore=false
StrictKeys=yes

[Locale]
Timezone=America/New_York
Language=en_US
EOF

    dd if=/dev/zero of=/home/user/app_restore/data/dummy_backup.bin bs=1024 count=15360 2>/dev/null

    chown -R user:user /home/user/app_restore
    chmod -R 777 /home/user
