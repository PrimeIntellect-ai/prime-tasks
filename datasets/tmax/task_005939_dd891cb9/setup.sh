#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the setup script
    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import tarfile
import shutil

# Base paths
home_dir = "/home/user"
os.makedirs(home_dir, exist_ok=True)
archive_path = os.path.join(home_dir, "legacy_docs.zip")
staging_dir = os.path.join(home_dir, "setup_staging")

os.makedirs(staging_dir, exist_ok=True)

# Create engineering tar.gz
eng_dir = os.path.join(staging_dir, "engineering")
api_dir = os.path.join(eng_dir, "api")
os.makedirs(api_dir, exist_ok=True)

with open(os.path.join(api_dir, "auth.md"), "w") as f:
    f.write("## API Authentication\nUse JWT tokens.")
with open(os.path.join(api_dir, "endpoints.txt"), "w") as f:
    f.write("GET /users\nPOST /users")

eng_tar_path = os.path.join(staging_dir, "engineering.tar.gz")
with tarfile.open(eng_tar_path, "w:gz") as tar:
    tar.add(eng_dir, arcname="engineering")

# Create sales zip
sales_dir = os.path.join(staging_dir, "sales")
pitch_dir = os.path.join(sales_dir, "pitch")
os.makedirs(pitch_dir, exist_ok=True)

with open(os.path.join(pitch_dir, "deck.txt"), "w") as f:
    f.write("Slide 1: Intro\nSlide 2: Synergy")
with open(os.path.join(pitch_dir, "contacts.md"), "w") as f:
    f.write("# Contacts\n- John Doe\n- Jane Smith")

sales_zip_path = os.path.join(staging_dir, "sales.zip")
with zipfile.ZipFile(sales_zip_path, "w") as z:
    for root, dirs, files in os.walk(sales_dir):
        for file in files:
            filepath = os.path.join(root, file)
            arcname = os.path.relpath(filepath, staging_dir)
            z.write(filepath, arcname)

# Create the final legacy_docs.zip
with zipfile.ZipFile(archive_path, "w") as z:
    z.write(eng_tar_path, "engineering.tar.gz")
    z.write(sales_zip_path, "sales.zip")

# Clean up staging
shutil.rmtree(staging_dir)
EOF

    # Run the setup script
    python3 /tmp/setup.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
