#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/backups

    # Create valid archive 1
    mkdir -p /tmp/cfg1
    echo "data" > /tmp/cfg1/config.txt
    tar -czf /home/user/backups/cfg_01.tar.gz -C /tmp cfg1

    # Create valid archive 2 (Processed)
    mkdir -p /tmp/cfg2
    echo "data2" > /tmp/cfg2/config.txt
    tar -czf /home/user/backups/cfg_02.tar.gz -C /tmp cfg2

    # Create corrupted archive (Pending)
    echo "This is not a tarball" > /home/user/backups/cfg_03.tar.gz

    # Create valid archive 4 (Pending)
    mkdir -p /tmp/cfg4
    echo "data4" > /tmp/cfg4/config.txt
    tar -czf /home/user/backups/cfg_04.tar.gz -C /tmp cfg4

    # Create the log file
    cat <<EOF > /home/user/backup_events.log
[Event ID: 101]
Type: ConfigBackup
File: /home/user/backups/cfg_01.tar.gz
Status: Pending

[Event ID: 102]
Type: ConfigBackup
File: /home/user/backups/cfg_02.tar.gz
Status: Processed

[Event ID: 103]
Type: ConfigBackup
File: /home/user/backups/cfg_03.tar.gz
Status: Pending

[Event ID: 104]
Type: ConfigBackup
File: /home/user/backups/cfg_04.tar.gz
Status: Pending
EOF

    # Create initial state file
    echo '{"valid_backups": []}' > /home/user/state.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
