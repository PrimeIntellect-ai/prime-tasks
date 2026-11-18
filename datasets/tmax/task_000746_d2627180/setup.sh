#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/tools
    mkdir -p /home/user/mock_root/etc
    mkdir -p /home/user/mnt_restore

    cat << 'EOF' > /home/user/tools/fetch_backup
#!/usr/bin/env python3
import sys
import tarfile
import json

print("Operator PIN: ", end="", flush=True)
pin = sys.stdin.readline().strip()
if pin == "8374":
    print("Success")
    with open("/home/user/metadata.json", "w") as f:
        json.dump({"username": "backup_admin"}, f)

    with tarfile.open("/home/user/backup.tar", "w") as tar:
        tar.add("/home/user/metadata.json", arcname="metadata.json")
    sys.exit(0)
else:
    print("Failed")
    sys.exit(1)
EOF
    chmod +x /home/user/tools/fetch_backup

    cat << 'EOF' > /home/user/mock_root/etc/fstab
/dev/sda1 / ext4 defaults 1 1
EOF

    cat << 'EOF' > /home/user/mock_root/etc/passwd
root:x:0:0:root:/root:/bin/bash
user:x:1000:1000:user:/home/user:/bin/bash
backup_admin:x:1001:1001:Backup Admin:/home/backup_admin:/bin/bash
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
