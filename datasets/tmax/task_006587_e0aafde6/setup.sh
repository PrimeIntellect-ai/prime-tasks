#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/backup_data

    cat << 'EOF' > /home/user/restore.py
#!/usr/bin/env python3
import os
import subprocess
import sys

# Simulating restore operation
log_dir = os.path.join(os.environ.get('HOME', '/tmp'), 'logs')
log_file = os.path.join(log_dir, 'restore.log')
fallback_log = '/tmp/fallback.log'

try:
    if not os.path.exists(log_dir):
        os.makedirs(log_dir, exist_ok=True)

    # Relies on standard PATH to find tar
    result = subprocess.run(['tar', '--version'], capture_output=True, text=True)
    if result.returncode == 0:
        with open(log_file, 'w') as f:
            f.write("RESTORE JOB: SUCCESS\n")
        print("Restore logged successfully.")
    else:
        raise Exception("tar command failed")
except Exception as e:
    with open(fallback_log, 'w') as f:
        f.write(f"RESTORE JOB: FAILED - {str(e)}\n")
    print("Restore failed, writing to fallback.")
    sys.exit(1)
EOF
    chmod +x /home/user/restore.py

    cat << 'EOF' > /home/user/run_wrapper.sh
#!/bin/bash
# Simulates a stripped cron environment
env -i python3 /home/user/restore.py
EOF
    chmod +x /home/user/run_wrapper.sh

    chmod -R 777 /home/user
