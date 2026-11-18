#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import tarfile
import shutil

# Ensure home directory structure
base_dir = "/home/user"
os.makedirs(base_dir, exist_ok=True)

# Create doc_config.json
config_data = {
    "api": "api_reference",
    "setup": "installation",
    "legacy": "archive",
    "auth": "security"
}
with open(os.path.join(base_dir, "doc_config.json"), "w", encoding="utf-8") as f:
    json.dump(config_data, f)

# Create raw files for the tarball
setup_dir = os.path.join(base_dir, ".task_setup")
os.makedirs(os.path.join(setup_dir, "folder_a", "subfolder"), exist_ok=True)
os.makedirs(os.path.join(setup_dir, "folder_b"), exist_ok=True)

files = [
    ("folder_a/api_v1_endpoints.md", "UTF-8", "# API v1\nEndpoints list."),
    ("folder_a/subfolder/legacy_notes.txt", "UTF-16LE", "Old notes from 2015."),
    ("folder_b/Setup_guide.md", "UTF-8", "# Setup\nHow to install."),
    ("folder_b/random_thoughts.txt", "UTF-16LE", "Just some random notes."),
    ("folder_b/AUTH_flow.txt", "UTF-8", "OAuth2 flow details."),
    ("folder_a/ignore_me.jpg", "binary", b"\xFF\xD8\xFF\xE0\x00\x10\x4A\x46\x49\x46\x00\x01")
]

for rel_path, enc, content in files:
    full_path = os.path.join(setup_dir, rel_path)
    if enc == "binary":
        with open(full_path, "wb") as f:
            f.write(content)
    else:
        with open(full_path, "w", encoding=enc) as f:
            f.write(content)

# Create tar.gz
tar_path = os.path.join(base_dir, "legacy_docs.tar.gz")
with tarfile.open(tar_path, "w:gz") as tar:
    tar.add(setup_dir, arcname=".")

# Cleanup setup dir
shutil.rmtree(setup_dir)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
