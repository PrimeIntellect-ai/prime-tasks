#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Execute the python setup script to create the exact initial state
    python3 << 'EOF'
import os
import tarfile
import shutil

os.makedirs("mock_docs/dept_a/nested", exist_ok=True)
os.makedirs("mock_docs/dept_b", exist_ok=True)
os.makedirs("mock_docs/dept_c", exist_ok=True)

# Create text files
with open("mock_docs/dept_a/file1.txt", "w") as f:
    f.write("Welcome to AcmeCorp. AcmeCorp is the best.\n")

with open("mock_docs/dept_a/nested/file2.md", "w") as f:
    f.write("This file mentions ZenithInc already, no AcmeCorp here.\n")

with open("mock_docs/dept_b/file3.txt", "w") as f:
    f.write("AcmeCorp acquired another company today.\n")

# Create binary files
with open("mock_docs/dept_c/legacy1.bin", "wb") as f:
    f.write(b"BDOC\x00\x01\x02\x03\x04\x05")

with open("mock_docs/dept_c/legacy2.dat", "wb") as f:
    f.write(b"JUNK\x00\x01\x02\x03\x04\x05")

with open("mock_docs/dept_a/nested/legacy3.bin", "wb") as f:
    f.write(b"BDOC\xff\xff\xff\xff")

# Create tarball
with tarfile.open("/home/user/raw_docs.tar.gz", "w:gz") as tar:
    tar.add("mock_docs", arcname="raw_docs")

# Cleanup mock_docs
shutil.rmtree("mock_docs")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
