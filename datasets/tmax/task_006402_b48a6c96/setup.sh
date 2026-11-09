#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/workspace
    mkdir -p /home/user/extracted
    mkdir -p /home/user/elf_master
    mkdir -p /home/user/log_links

    mkdir -p /tmp/gen_backups
    cd /tmp/gen_backups

    # Helper to create logs
    create_log() {
      local status=$1
      cat <<EOF > backup.log
System Check: OK
--- BACKUP START ---
Timestamp: 2023-10-24T10:00:00Z
Status: $status
Message: Backup completed with status $status
--- BACKUP END ---
Cleanup: DONE
EOF
    }

    # Archive 1 (Success)
    mkdir -p app_v1/bin
    cp /bin/ls app_v1/bin/app
    cp /bin/cat app_v1/bin/helper
    create_log "SUCCESS"
    mv backup.log app_v1/
    tar -czf /home/user/backups/app_v1.tar.gz app_v1/

    # Archive 2 (Success, overlapping binaries)
    mkdir -p app_v2/bin
    cp /bin/ls app_v2/bin/app
    cp /bin/echo app_v2/bin/tool
    create_log "SUCCESS"
    mv backup.log app_v2/
    tar -czf /home/user/backups/app_v2.tar.gz app_v2/

    # Archive 3 (Corrupt)
    mkdir -p app_v3/bin
    cp /bin/date app_v3/bin/app
    create_log "SUCCESS"
    mv backup.log app_v3/
    tar -czf /home/user/backups/app_v3.tar.gz app_v3/
    # Corrupt the archive by overwriting the first few bytes
    dd if=/dev/urandom of=/home/user/backups/app_v3.tar.gz bs=1 count=10 conv=notrunc

    # Archive 4 (Failed)
    mkdir -p app_v4/bin
    cp /bin/cat app_v4/bin/app
    create_log "FAILED"
    mv backup.log app_v4/
    tar -czf /home/user/backups/app_v4.tar.gz app_v4/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
