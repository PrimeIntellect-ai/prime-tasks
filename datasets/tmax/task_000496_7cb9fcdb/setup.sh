#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pexpect

    # Create vendored package directory
    mkdir -p /app/py-restore-util-1.2.0/restore_util

    # Create pyproject.toml with deliberate syntax error
    cat << 'EOF' > /app/py-restore-util-1.2.0/pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "py-restore-util"
version = "1.2.0"
dependencies = []

[project.scripts]
restore-util = "restore_util.cli:main
EOF

    # Create __init__.py
    touch /app/py-restore-util-1.2.0/restore_util/__init__.py

    # Create cli.py with REQUIRE_SSH_KEY check and interactive prompt
    cat << 'EOF' > /app/py-restore-util-1.2.0/restore_util/cli.py
import sys
import os

def main():
    if os.environ.get("REQUIRE_SSH_KEY", "1") == "1":
        raise Exception("Fatal: SSH key required but rejected by server configuration.")

    if len(sys.argv) < 3 or sys.argv[1] != "extract":
        print("Usage: restore-util extract <BACKUP_ID>")
        sys.exit(1)

    backup_id = sys.argv[2]

    sys.stdout.write("Archive Password: ")
    sys.stdout.flush()
    password = sys.stdin.readline().strip()

    if password != "OperatorDeploy99!":
        print("Invalid password")
        sys.exit(1)

    print(f"/data/backup_{backup_id}/config.yaml")
    print(f"/data/backup_{backup_id}/database.db")
    print(f"/data/backup_{backup_id}/media/image1.png")

if __name__ == "__main__":
    main()
EOF

    # Create oracle directory and script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/auto_restore_oracle.py
import sys
import pexpect
import json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    backup_id = sys.argv[1]
    child = pexpect.spawn(f'restore-util extract {backup_id}', encoding='utf-8')
    child.expect('Archive Password: ')
    child.sendline('OperatorDeploy99!')
    child.expect(pexpect.EOF)

    output = child.before
    files = []
    for line in output.splitlines():
        line = line.strip()
        if line and line.startswith('/data/'):
            files.append(line)

    files.sort()
    print(json.dumps({"restored_files": files}))

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/auto_restore_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
