#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import tarfile

work_dir = "/home/user"
os.makedirs(work_dir, exist_ok=True)

log_content = """[INFO] 2023-01-01 10:00:00 Booting system...
[INFO] 2023-01-01 10:00:05 Loading modules.
[ERROR] 2023-01-01 10:00:10 Failed to load config
  Line 1: missing semicolon
  Line 2: invalid syntax
  File "config.xml", line 42
[WARN] 2023-01-01 10:00:15 Retrying with defaults
[INFO] 2023-01-01 10:00:20 Running...
[ERROR] 2023-01-02 11:30:00 NullPointerException
  at module.main(Main.java:42)
  at system.run(System.java:10)
[INFO] 2023-01-02 11:35:00 Shutting down gracefully.
"""

log_path = os.path.join(work_dir, "application.log")
with open(log_path, "w", encoding="utf-16le") as f:
    f.write(log_content)

zip_path = os.path.join(work_dir, "logs.zip")
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
    zipf.write(log_path, "application.log")

tar_path = os.path.join(work_dir, "legacy_project_logs.tar.gz")
with tarfile.open(tar_path, "w:gz") as tar:
    tar.add(zip_path, arcname="logs.zip")

# Cleanup intermediates
os.remove(log_path)
os.remove(zip_path)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
