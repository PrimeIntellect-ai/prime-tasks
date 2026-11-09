#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/account_repo.git
    git init --bare /home/user/account_repo.git
    mkdir -p /home/user/scripts
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/scripts/sync_accounts.py
#!/usr/bin/env python3
import os
import sys

log_dir = os.environ.get('LOG_DIR', '.')
log_file = os.path.join(log_dir, 'sync.log')

try:
    with open(log_file, 'a') as f:
        f.write('Sync triggered\n')
    print("Sync completed successfully.")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
EOF
    chmod +x /home/user/scripts/sync_accounts.py

    chown -R user:user /home/user/account_repo.git /home/user/scripts /home/user/logs
    chmod -R 777 /home/user
