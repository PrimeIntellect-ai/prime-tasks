#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_export.py
#!/usr/bin/env python3
import sys
import os

print("Legacy Storage Exporter v1.0")
try:
    pwd = input("Enter admin password: ")
    if pwd != "cloud_admin_99":
        print("Auth failed!")
        sys.exit(1)

    path = input("Enter export path: ")
    print(f"Exporting to {path}...")

    os.makedirs(f"{path}/app1", exist_ok=True)
    os.makedirs(f"{path}/db_data", exist_ok=True)

    with open(f"{path}/app1/config.txt", "w") as f: 
        f.write("app1 config")
    with open(f"{path}/db_data/schema.sql", "w") as f: 
        f.write("CREATE TABLE;")

    print("Export complete.")
except EOFError:
    print("Interactive input required.")
    sys.exit(1)
EOF
    chmod +x /home/user/legacy_export.py

    cat << 'EOF' > /home/user/migration_fstab
# Cloud migration mount mappings
# source_in_export_data target_symlink_path

app1 /home/user/cloud_mounts/srv/app1
db_data /home/user/cloud_mounts/var/lib/db
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
