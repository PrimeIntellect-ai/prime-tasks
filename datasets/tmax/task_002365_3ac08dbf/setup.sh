#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    git config --global init.defaultBranch master

    mkdir -p /home/user/restore.git
    git init --bare /home/user/restore.git

    mkdir -p /home/user/app_src
    cd /home/user/app_src
    git init
    git remote add origin /home/user/restore.git
    echo 'print("Hello World")' > app.py
    git add app.py
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit -m "Initial commit"

    mkdir -p /home/user/restore.git/hooks
    cat << 'EOF' > /home/user/restore.git/hooks/pre-receive
#!/usr/bin/env python3
import sys
import subprocess

for line in sys.stdin:
    old_rev, new_rev, ref_name = line.strip().split()

    # Bug: using git log incorrectly, expecting bytes but trying to use string operations without decode,
    # or just a typo in the subprocess call.
    try:
        commit_msg = subprocess.check_output(['git', 'log', '--format=%B', '-n', '1', new_rev])
        # Intentional bug: commit_msg is bytes, trying to check string "RESTORE_TEST" in bytes will throw TypeError or always be false.
        if "RESTORE_TEST" not in commit_msg:
            print("Missing RESTORE_TEST token.")
            sys.exit(1)
    except Exception as e:
        # Fails silently by exiting 1
        sys.exit(1)

sys.exit(0)
EOF
    chmod +x /home/user/restore.git/hooks/pre-receive

    mkdir -p /home/user/deploy/staging
    mkdir -p /home/user/deploy/prod

    chmod -R 777 /home/user
