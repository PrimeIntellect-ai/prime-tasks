#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip bzip2 tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import shutil

base_dir = "/home/user/setup_temp"
os.makedirs(base_dir, exist_ok=True)

# Configurations definitions
configs = {
    "server_alpha": {
        "app.conf": "ServerName alpha\nPort 8080\nLogLevel debug\n# Valid comment\n",
        "system.conf": "OS Linux\nMemory 16G\n", # No changes needed
        "legacy.conf": "# DEPRECATED settings below\nOldSetting 1\nPort 8080\n"
    },
    "server_beta": {
        "db.conf": "DBName beta\nPort 8080\nLogLevel info\n",
        "cache.conf": "CacheSize 1G\nLogLevel debug\n  # DEPRECATED cache rule\n"
    },
    "server_gamma": {
        "web.conf": "Worker 4\nPort 80\nLogLevel warn\n" # No changes needed
    }
}

main_tar_path = "/home/user/config_backups.tar.gz"

with tarfile.open(main_tar_path, "w:gz") as main_tar:
    for server, files in configs.items():
        server_dir = os.path.join(base_dir, server)
        os.makedirs(server_dir, exist_ok=True)

        # Create bz2
        bz2_path = os.path.join(server_dir, "data.tar.bz2")
        with tarfile.open(bz2_path, "w:bz2") as bz2:
            for fname, content in files.items():
                fpath = os.path.join(server_dir, fname)
                with open(fpath, "w") as f:
                    f.write(content)
                bz2.add(fpath, arcname=fname)
                os.remove(fpath)

        # Create zip
        zip_path = os.path.join(server_dir, "backup.zip")
        with zipfile.ZipFile(zip_path, "w") as zf:
            zf.write(bz2_path, arcname="data.tar.bz2")
        os.remove(bz2_path)

        # Add to main tar
        main_tar.add(server_dir, arcname=server)

shutil.rmtree(base_dir)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
