#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/scripts /home/user/admin_workspace

    # Setup Python script
    cat << 'EOF' > /home/user/scripts/log_update.py
#!/usr/bin/env python3
import os
import sys
import datetime

dest = os.getenv('LOG_DEST', 'commits.log')
try:
    with open(dest, 'a') as f:
        f.write(f"Commit pushed at {datetime.datetime.now().isoformat()}\n")
except Exception as e:
    pass
EOF
    chmod +x /home/user/scripts/log_update.py

    # Setup Git bare repo and hook
    git init --bare /home/user/user_repo.git
    cat << 'EOF' > /home/user/user_repo.git/hooks/post-receive
#!/bin/bash
/home/user/scripts/log_update.py
EOF
    chmod +x /home/user/user_repo.git/hooks/post-receive

    # Global git config for setup
    git config --global user.email "admin@example.com"
    git config --global user.name "Admin"
    git config --global init.defaultBranch master

    # Setup Workspace
    cd /home/user/admin_workspace
    git init
    git remote add origin /home/user/user_repo.git
    touch init.txt
    git add init.txt
    git commit -m "Initial commit"
    git push -u origin master

    # Setup git config for user
    cat << 'EOF' > /home/user/.gitconfig
[user]
	name = Admin
	email = admin@example.com
[init]
	defaultBranch = master
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
