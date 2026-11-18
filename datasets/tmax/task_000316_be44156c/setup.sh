#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_deploy.py
#!/usr/bin/env python3
import json
import os
import sys

LOG_FILE = '/home/user/migration_log.json'

def main():
    try:
        service_name = input("Enter service name to migrate: ").strip()
        version = input("Enter target version: ").strip()
        pre_checks = input("Verify pre-checks passed? (yes/no): ").strip()

        if pre_checks != 'yes':
            print("Pre-checks failed. Aborting.")
            sys.exit(1)

        bring_online = input("Bring service online? (y/n): ").strip()

        status = "online" if bring_online == 'y' else "offline"

        # Load existing log
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, 'r') as f:
                try:
                    log_data = json.load(f)
                except:
                    log_data = {}
        else:
            log_data = {}

        log_data[service_name] = {
            "version": version,
            "status": status
        }

        with open(LOG_FILE, 'w') as f:
            json.dump(log_data, f, indent=4)

        print(f"Successfully migrated {service_name} to {version} ({status}).")

    except EOFError:
        print("\nUnexpected EOF. Migration aborted.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/legacy_deploy.py

    chmod -R 777 /home/user
