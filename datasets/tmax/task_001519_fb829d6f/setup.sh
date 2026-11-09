#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install expect, golang, and tzdata
    apt-get install -y expect golang tzdata

    mkdir -p /home/user

    cat << 'EOF' > /home/user/mock_fstab
# /etc/fstab: static file system information.
/dev/root / ext4 defaults 0 0
/dev/sda1 /home/user/metrics_mount ext4 defaults,noatime 0 2
/dev/sdb1 /home/user/backup xfs defaults 0 2
EOF

    cat << 'EOF' > /home/user/vault_log_fetch
#!/usr/bin/env python3
import sys
import time

def main():
    sys.stdout.write("Username: ")
    sys.stdout.flush()
    user = sys.stdin.readline().strip()

    sys.stdout.write("PIN: ")
    sys.stdout.flush()
    pin = sys.stdin.readline().strip()

    if user == "sre_admin" and pin == "998877":
        print("2024-01-10T02:15:00Z | Database failover")
        print("2024-01-15T14:45:00Z | API gateway timeout")
        print("2024-02-01T23:59:00Z | Scheduled maintenance")
    else:
        print("Authentication failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/vault_log_fetch

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
