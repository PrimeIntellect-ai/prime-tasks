#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/backups
    cd /home/user/backups

    cat << 'EOF' > app_a.log
System initialized.
Connecting to [OLD_STORAGE_NODE_55] for block storage...
[OLD_STORAGE_NODE_55] connected successfully.
Transferring 500MB.
EOF

    cat << 'EOF' > app_b.log
Warning: High latency detected.
[OLD_STORAGE_NODE_55] timeout waiting for flush.
Retry 1... [OLD_STORAGE_NODE_55] responded.
EOF

    cat << 'EOF' > app_c.log
Normal operations.
No storage nodes contacted.
EOF

    gzip app_a.log
    gzip app_b.log
    gzip app_c.log

    echo "This is just a plain text file pretending to be compressed." > corrupt_app_x.log.gz
    echo -e "\x00\x00\x00\x00Some binary garbage here" > corrupt_app_y.log.gz

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
