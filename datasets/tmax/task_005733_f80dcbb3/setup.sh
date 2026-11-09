#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/backups/data /home/user/bin

    cat << 'EOF' > /home/user/bin/init_backup.py
#!/usr/bin/env python3
import sys
import json

def main():
    try:
        src = input("Source directory: ").strip()
        dst = input("Destination directory: ").strip()
        ret = input("Retention days: ").strip()
        confirm = input("Proceed with setup? (y/n): ").strip()

        if confirm.lower() == 'y':
            with open("/home/user/backup_configured.json", "w") as f:
                json.dump({"src": src, "dst": dst, "retention": ret}, f)
            print("Configuration successful.")
        else:
            print("Aborted.")
            sys.exit(1)
    except EOFError:
        print("Unexpected EOF")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/bin/init_backup.py

    cat << 'EOF' > /home/user/bin/run_backup.sh
#!/bin/bash
echo "Running backup..."
EOF

    chmod +x /home/user/bin/run_backup.sh

    chmod -R 777 /home/user
