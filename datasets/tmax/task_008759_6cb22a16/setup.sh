#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import json
import shutil

raw_data_dir = "/home/user/raw_data"
mapping_file = "/home/user/project_mapping.json"

mapping = {
    "TUNDRA_STUDY": "TUN",
    "GLACIER_MELT": "GLA",
    "OCEAN_TEMP": "OCE"
}
with open(mapping_file, 'w') as f:
    json.dump(mapping, f)

os.makedirs(os.path.join(raw_data_dir, "site_A", "2021"), exist_ok=True)
os.makedirs(os.path.join(raw_data_dir, "site_A", "2022"), exist_ok=True)
os.makedirs(os.path.join(raw_data_dir, "site_B", "logs"), exist_ok=True)

def make_tar(path, project_name):
    meta_path = "/tmp/metadata.txt"
    with open(meta_path, 'w') as f:
        f.write(f"Author: Smith\nProject: {project_name}\nDate: 2021\n")

    data_path = "/tmp/data.bin"
    with open(data_path, 'wb') as f:
        f.write(os.urandom(1024))

    with tarfile.open(path, "w:gz") as tar:
        tar.add(meta_path, arcname="metadata.txt")
        tar.add(data_path, arcname="data.bin")

def make_zip(path, project_name):
    with zipfile.ZipFile(path, 'w') as zf:
        zf.writestr("metadata.txt", f"Author: Doe\nProject: {project_name}\nDate: 2022\n")
        zf.writestr("data.bin", os.urandom(1024))

make_tar(os.path.join(raw_data_dir, "site_A", "2021", "reading_01.tar.gz"), "TUNDRA_STUDY")
make_zip(os.path.join(raw_data_dir, "site_A", "2022", "reading_02.zip"), "GLACIER_MELT")
make_tar(os.path.join(raw_data_dir, "site_B", "logs", "reading_03.tar.gz"), "OCEAN_TEMP")
make_zip(os.path.join(raw_data_dir, "site_B", "logs", "reading_04.zip"), "UNKNOWN_PROJ")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
