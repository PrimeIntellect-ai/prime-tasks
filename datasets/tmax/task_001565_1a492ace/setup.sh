#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip acl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/source
cat << 'EOF' > /home/user/source/legacy_batch.py
#!/usr/bin/env python3
import os
import sys
import stat
import subprocess
import datetime

def main():
    log_dir = "/home/user/deploy/logs"
    log_file = os.path.join(log_dir, "execution.log")

    # 1. Check if running from correct location
    if not os.path.abspath(__file__).startswith("/home/user/deploy/"):
        print("Error: Not running from deploy directory.")
        sys.exit(1)

    # 2. Check permissions (0500)
    st = os.stat(__file__)
    perms = stat.S_IMODE(st.st_mode)
    if perms != 0o500:
        print(f"Error: Incorrect permissions. Expected 0500, got {oct(perms)}")
        sys.exit(1)

    # 3. Check environment variables
    if os.environ.get("TZ") != "Pacific/Fiji":
        print("Error: TZ environment variable not set to Pacific/Fiji")
        sys.exit(1)

    if os.environ.get("MIGRATION_LOCALE") != "C.UTF-8":
        print("Error: MIGRATION_LOCALE environment variable not set to C.UTF-8")
        sys.exit(1)

    # 4. Write log file (ACL inheritance will be checked by test suite)
    with open(log_file, "w") as f:
        f.write("MIGRATION_SUCCESSFUL\n")
        f.write(f"Executed at: {datetime.datetime.now()}\n")

if __name__ == "__main__":
    main()
EOF

chmod -R 777 /home/user
chmod 644 /home/user/source/legacy_batch.py
