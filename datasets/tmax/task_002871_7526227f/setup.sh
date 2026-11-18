#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/mail_manager/config

    cat << 'EOF' > /home/user/mail_manager/run_job.sh
#!/usr/bin/env bash
export PATH=/usr/bin:/bin
cd /tmp
python3 /home/user/mail_manager/generate_report.py
EOF
    chmod +x /home/user/mail_manager/run_job.sh

    cat << 'EOF' > /home/user/mail_manager/config/aliases.conf
# System Aliases
admin: admin@example.com
support: support@example.com

# Marketing team
marketing marketing@example.com

# DevOps team
devops devops@example.com missingcolon
EOF

    cat << 'EOF' > /home/user/mail_manager/generate_report.py
import sys
import os

def main():
    # Bug 1: relative path
    with open('config/aliases.conf', 'r') as f:
        lines = f.readlines()

    valid_aliases = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'): continue

        # Bug 2: no robust error handling for missing colon
        parts = line.split(':')
        valid_aliases.append(f"{parts[0].strip()} -> {parts[1].strip()}")

    # Bug 3: relative path for output
    with open('report.log', 'w') as out:
        for alias in valid_aliases:
            out.write(alias + '\n')

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
