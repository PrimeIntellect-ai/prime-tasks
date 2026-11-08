#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip file zip unzip tar
pip3 install pytest

# Create the initial state using Python
python3 -c '
import os
import tarfile
import zipfile

home_dir = "/home/user"
os.makedirs(home_dir, exist_ok=True)
legacy_tar_path = os.path.join(home_dir, "legacy_configs.tar.gz")
master_zip_path = os.path.join(home_dir, "master_configs.zip")

configs = {
    "db.conf": "host=localhost\nport=5432\ndesc=Café database\n",
    "web.conf": "server=nginx\nworkers=4\nwelcome=Bienvenue à la page\n"
}

os.makedirs("/tmp/legacy_setup", exist_ok=True)
with tarfile.open(legacy_tar_path, "w:gz") as tar:
    for filename, content in configs.items():
        filepath = f"/tmp/legacy_setup/{filename}"
        with open(filepath, "w", encoding="iso-8859-1") as f:
            f.write(content)
        tar.add(filepath, arcname=filename)

with zipfile.ZipFile(master_zip_path, "w") as zf:
    zf.writestr("existing.conf", "existing=true\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
