#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo g++ build-essential libarchive-dev libssl-dev
    pip3 install pytest

    # Create the user early so we can place files in their home directory
    useradd -m -s /bin/bash user || true

    # Run the setup script to create the tarballs
    cat << 'EOF' > /tmp/setup.py
import tarfile
import os

# Create workspace
os.makedirs("/home/user/extracted", exist_ok=True)
os.makedirs("/tmp/setup", exist_ok=True)

# Create safe files
with open("/tmp/setup/safe1.txt", "w") as f: f.write("Safe content 1\n")
with open("/tmp/setup/safe2.txt", "w") as f: f.write("Safe content 2\n")
with open("/tmp/setup/nested_safe.txt", "w") as f: f.write("Nested safe\n")
with open("/tmp/setup/malicious.txt", "w") as f: f.write("Malicious!\n")

# Create nested tar
with tarfile.open("/tmp/setup/nested.tar", "w") as ntar:
    ntar.add("/tmp/setup/nested_safe.txt", arcname="data/nested_safe.txt")
    # Malicious file in nested tar
    malicious_info = ntar.gettarinfo("/tmp/setup/malicious.txt", arcname="../nested_malicious.txt")
    ntar.addfile(malicious_info, open("/tmp/setup/malicious.txt", "rb"))

# Create main tar
with tarfile.open("/home/user/input.tar", "w") as main_tar:
    main_tar.add("/tmp/setup/safe1.txt", arcname="safe1.txt")
    main_tar.add("/tmp/setup/safe2.txt", arcname="docs/safe2.txt")
    main_tar.add("/tmp/setup/nested.tar", arcname="nested.tar")

    # Malicious absolute path
    abs_info = main_tar.gettarinfo("/tmp/setup/malicious.txt", arcname="/etc/hacked.txt")
    main_tar.addfile(abs_info, open("/tmp/setup/malicious.txt", "rb"))

    # Malicious traversal path
    trav_info = main_tar.gettarinfo("/tmp/setup/malicious.txt", arcname="docs/../../hacked2.txt")
    main_tar.addfile(trav_info, open("/tmp/setup/malicious.txt", "rb"))

os.system("rm -rf /tmp/setup")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Allow user to use sudo without password for package installation if needed
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    chmod -R 777 /home/user
